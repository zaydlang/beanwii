#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ogcsys.h>
#include <gccore.h>
#include <network.h>
#include <wiiuse/wpad.h>

static lwp_t httd_handle = (lwp_t) NULL;

void* httpd(void* arg);

static uint8_t ATTRIBUTE_ALIGN(32) iram_code[8192];
int main(int argc, char** argv) {
    VIDEO_Init();
    WPAD_Init();

    GXRModeObj* rmode = VIDEO_GetPreferredMode(NULL);
    void* framebuffer = MEM_K0_TO_K1(SYS_AllocateFramebuffer(rmode));
    console_init(framebuffer, 20, 20, rmode->fbWidth, rmode->xfbHeight, rmode->fbWidth * VI_DISPLAY_PIX_SZ);

    VIDEO_Configure(rmode);
    VIDEO_SetNextFramebuffer(framebuffer);
    VIDEO_SetBlack(false);
    VIDEO_Flush();
    VIDEO_WaitVSync();
    if (rmode->viTVMode & VI_NON_INTERLACE) {
        VIDEO_WaitVSync();
    }

    printf("configuring network...\n");

    char localip[16] = {0};
    char gateway[16] = {0};
    char netmask[16] = {0};
    s32 if_config_result = if_config(localip, netmask, gateway, true, 20);
    if (if_config_result >= 0) {
        printf("network configured, ip: %s\n", localip);
        LWP_CreateThread(&httd_handle, httpd, localip, NULL, 64 * 1024, 50);
    } else {
        printf("network configuration failed!: %d\n", if_config_result);
    }

    while (true) {
        VIDEO_WaitVSync();
        WPAD_ScanPads();

        int buttons_down = WPAD_ButtonsDown(0);

        if (buttons_down & WPAD_BUTTON_A) {
            exit(0);
        }
    }

    return 0;
}


void* httpd(void* arg) {
    struct sockaddr_in client;
    struct sockaddr_in server;

    int sock = net_socket(AF_INET, SOCK_STREAM, IPPROTO_IP);

    if (sock == INVALID_SOCKET) {
        printf("Cannot create a socket!\n");
    } else {
        memset(&server, 0, sizeof(server));
        memset(&client, 0, sizeof(client));

        server.sin_family = AF_INET;
        server.sin_port = htons(1234);
        server.sin_addr.s_addr = INADDR_ANY;
        int net_bind_result = net_bind(sock, (struct sockaddr*) &server, sizeof(server));

        if (net_bind_result) {
            printf("Error %d binding socket!\n", net_bind_result);
        } else {
            int net_listen_result = net_listen(sock, 5);
            if (net_listen_result) {
                printf("Error %d listening!\n", net_listen_result);
            } else {
                while (true) {
                    u32 clientlen = sizeof(client);
                    int csock = net_accept(sock, (struct sockaddr*) &client, &clientlen);

                    if (csock < 0) {
                        printf("Error connecting socket %d!\n", csock);
                        while (true);
                    }

                    printf("Connecting port %d from %s\n", client.sin_port, inet_ntoa(client.sin_addr));
                    
                    // First read the header to get sizes
                    u8 header[10];
                    int header_received = net_recv(csock, header, 10, 0);
                    
                    if (header_received != 10) {
                        printf("Failed to receive header: %d bytes\n", header_received);
                        net_close(csock);
                        continue;
                    }
                    
                    // Parse header to get expected packet size
                    u16 magic = (header[0] << 8) | header[1];
                    u16 test_case_length = (header[2] << 8) | header[3];
                    u16 test_case_index = (header[4] << 8) | header[5];
                    u16 num_test_cases = (header[6] << 8) | header[7];
                    u16 iram_code_length = (header[8] << 8) | header[9];
                    
                    if (magic != 0xBEEF) {
                        printf("Invalid magic in header: 0x%04X\n", magic);
                        net_close(csock);
                        continue;
                    }
                    
                    int remaining_bytes = iram_code_length + (31 * num_test_cases * 2) + (31 * 2) + (test_case_length * num_test_cases);
                    int total_size = 10 + remaining_bytes;
                    
                    printf("Expected total packet size: %d bytes\n", total_size);
                    
                    // Allocate buffer for full packet
                    u8* full_packet = malloc(total_size);
                    if (!full_packet) {
                        printf("Failed to allocate %d bytes\n", total_size);
                        net_close(csock);
                        continue;
                    }
                    
                    // Copy header to full packet
                    memcpy(full_packet, header, 10);
                    
                    // Read remaining data
                    int total_received = 10;
                    while (total_received < total_size) {
                        int bytes_received = net_recv(csock, full_packet + total_received, total_size - total_received, 0);
                        if (bytes_received <= 0) {
                            printf("Failed to receive remaining data: %d\n", bytes_received);
                            break;
                        }

                        total_received += bytes_received;
                    }
                    
                    if (total_received == total_size) {
                        printf("Received complete packet: %d bytes\n", total_size);
                        
                        if (total_received < 10) {
                            printf("Packet too short: %d bytes\n", total_size);
                            return;
                        }

                        int offset = 0;
                        
                        u16 magic = (full_packet[offset] << 8) | full_packet[offset + 1];
                        offset += 2;
                        
                        if (magic != 0xBEEF) {
                            printf("Invalid magic: 0x%04X\n", magic);
                            return;
                        }

                        u16 test_case_length = (full_packet[offset] << 8) | full_packet[offset + 1];
                        offset += 2;
                        
                        u16 test_case_index = (full_packet[offset] << 8) | full_packet[offset + 1];
                        offset += 2;
                        
                        u16 num_test_cases = (full_packet[offset] << 8) | full_packet[offset + 1];
                        offset += 2;
                        
                        u16 iram_code_length = (full_packet[offset] << 8) | full_packet[offset + 1];
                        offset += 2;

                        int expected_length = 10 + iram_code_length + (31 * num_test_cases * 2) + (31 * 2) + (test_case_length * num_test_cases);
                        if (total_size != expected_length) {
                            printf("Invalid packet length: %d (expected %d)\n", total_size, expected_length);
                            return;
                        }

                        u8* iram_code_unaligned = &full_packet[offset];
                        offset += iram_code_length;
                        memcpy(iram_code, iram_code_unaligned, iram_code_length);
                        
                        u16* test_cases_accumulators = (u16*)&full_packet[offset];
                        offset += 31 * num_test_cases * 2;
                        
                        u16* test_cases_accumulator_indices = (u16*)&full_packet[offset];
                        offset += 31 * 2;
                        
                        u8* test_cases_data = &full_packet[offset];
                        
                        printf("Parsed DSP command:\n");
                        printf("  test_case_length: %d\n", test_case_length);
                        printf("  test_case_index: %d\n", test_case_index);
                        printf("  num_test_cases: %d\n", num_test_cases);
                        printf("  iram_code_length: %d\n", iram_code_length);

                        u16* result_data = malloc(31 * 2 * num_test_cases);
                        dsptask_t task;

                        int kkk = 0;
                        for (int i = 0; i < num_test_cases; i++) {
                            DSP_Init();
                            AUDIO_Init(NULL);
                            AUDIO_StopDMA();
                            AUDIO_SetDSPSampleRate(AI_SAMPLERATE_48KHZ);
                            DSP_Reset();

                            memset(&task, 0, sizeof(dsptask_t));
                            memcpy(&iram_code[test_case_index], &test_cases_data[i * test_case_length], test_case_length);
                            
                            // printf the first few bytes iram code for debugging
                            // for (int j = 0; j < (iram_code_length < 16 ? iram_code_length : 16); j++) {
                                // printf("%02X ", iram_code[j]);
                            // }

                            for (int j = 0; j < 31; j++) {
                                uint16_t idx = test_cases_accumulator_indices[j];
                                uint16_t acc = test_cases_accumulators[i * 31 + j];
                                memcpy(&iram_code[idx], &acc, 2);
                            }
                            task.prio = 255;
                            task.iram_maddr = (void*)MEM_VIRTUAL_TO_PHYSICAL(iram_code);
                            task.iram_len = iram_code_length;
                            task.iram_addr = 0x0000;
                            task.dram_maddr = (void*)MEM_VIRTUAL_TO_PHYSICAL(0x80000000);
                            task.dram_len = 8192;
                            task.dram_addr = 0x0000;
                            task.init_vec = 0;
                            task.res_cb = NULL;
                            task.req_cb = NULL;
                            task.init_cb = NULL;
                            task.done_cb = NULL;

		                    DCFlushRange(iram_code, iram_code_length);
                            DSP_AddTask(&task);

                            for (int j = 0; j < 31; j++) {
                                while(!DSP_CheckMailFrom());
                                uint32_t mb = DSP_ReadMailFrom();
                                result_data[i * 31 + j] = mb & 0xFFFF;
                            }
                            printf("Test case %d done\n", i + 1);
                        }
                        
                        net_send(csock, result_data, 31 * 2 * num_test_cases, 0);
                        free(result_data);
                    } else {
                        printf("Incomplete packet: %d/%d bytes\n", total_received, total_size);
                    }
                    
                    free(full_packet);

                    net_close(csock);
                }
            }
        }
    }

    return NULL;
}
