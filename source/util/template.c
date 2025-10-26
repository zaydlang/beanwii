#include <stdio.h>
#include <stdlib.h>
#include <gccore.h>
#include <wiiuse/wpad.h>
#include <aesndlib.h>
#include <gcmodplay.h>
#include "../iram_code.h"
// include generated header
#include "technique_mod.h"

static void *xfb = NULL;
static GXRModeObj *rmode = NULL;
static MODPlay play;

dsptask_t task;
//---------------------------------------------------------------------------------
int main(int argc, char **argv) {
//---------------------------------------------------------------------------------

	// Initialise the video system
	VIDEO_Init();

	// Initialise the attached controllers
	// WPAD_Init();

	// Initialise the audio subsystem

	// Obtain the preferred video mode from the system
	// This will correspond to the settings in the Wii menu
	rmode = VIDEO_GetPreferredMode(NULL);

	// Allocate memory for the display in the uncached region
	xfb = MEM_K0_TO_K1(SYS_AllocateFramebuffer(rmode));

	// Initialise the console, required for printf
	console_init(xfb,20,20,rmode->fbWidth,rmode->xfbHeight,rmode->fbWidth*VI_DISPLAY_PIX_SZ);

	// Set up the video registers with the chosen mode
	VIDEO_Configure(rmode);

	// Tell the video hardware where our display memory is
	VIDEO_SetNextFramebuffer(xfb);

	// Make the display visible
	VIDEO_SetBlack(false);

	// Flush the video register changes to the hardware
	VIDEO_Flush();

	// Wait for Video setup to complete
	VIDEO_WaitVSync();
	if(rmode->viTVMode&VI_NON_INTERLACE) VIDEO_WaitVSync();


	// The console understands VT terminal escape codes
	// This positions the cursor on row 2, column 0
	// we can use variables for this with format codes too
	// e.g. printf ("\x1b[%d;%dH", row, column );
	printf("\x1b[2;0H");
		
	ISFS_Initialize();
	ISFS_Delete("/results");
	ISFS_CreateFile("/results",0,0,0,0);
	int fd = IOS_Open("/results", 2 /* 2 = write, 1 = read */);


	for (int i = 0; i < num_test_cases; i++) {

		DSP_Init();
		AUDIO_Init(NULL);
		AUDIO_StopDMA();
		AUDIO_SetDSPSampleRate(AI_SAMPLERATE_48KHZ);
		DSP_Reset();

		memset(&task, 0, sizeof(dsptask_t));
		memcpy(&iram_code[test_case_index], &test_cases[i * test_case_length], test_case_length);
		
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
		task.dram_len = 0;
		task.dram_addr = 0x0000;
		task.init_vec = 0;
		task.res_cb = NULL;
		task.req_cb = NULL;
		task.init_cb = NULL;
		task.done_cb = NULL;

		// printf("Test case %d\n", i);
		DSP_AddTask(&task);

		// printf("Running test case %d/%d\n", i + 1, num_test_cases);

		for (int i = 0; i < 31; i++) {
			while(!DSP_CheckMailFrom());
			uint16_t mb = DSP_ReadMailFrom() & 0xFFFF;
			IOS_Write(fd, &mb, 2);
		}
		printf("Test case %d done\n", i + 1);
	}

		printf("Done\n");
		IOS_Close(fd);

	return 0;
}
