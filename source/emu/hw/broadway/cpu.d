module emu.hw.broadway.cpu;

import core.bitop;
import emu.hw.broadway.exception_type;
import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.broadway.state;
import emu.hw.broadway.jit.emission.return_value;
import emu.hw.broadway.jit.jit;
import emu.hw.ipc.ipc;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import util.bitop;
import util.endian;
import util.log;
import util.number;
import std.stdio;

int bazinga = 0;
__gshared 
    bool biglog = false;
final class Broadway {

    public  BroadwayState       state;
    private Mem                 mem;
    private Jit                 jit;
    private HleContext          hle_context;
    public InterruptController interrupt_controller;
    private size_t              ringbuffer_size;

    public  bool                should_log;

    private Scheduler           scheduler;

    private ulong decrementer_event;

    public this(size_t ringbuffer_size) {
        this.ringbuffer_size = ringbuffer_size;
        this.interrupt_controller = new InterruptController();
        this.interrupt_controller.connect_cpu(this);
        this.should_log = false;
    }

    public void connect_mem(Mem mem) {
        this.mem = mem;
        this.hle_context = new HleContext(&this.mem);

        jit = new Jit(JitConfig(
            cast(ReadHandler)  (&this.mem.read_be_u8)   .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u16)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u32)  .funcptr,
            cast(ReadHandler)  (&this.mem.read_be_u64)  .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u8)  .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u16) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u32) .funcptr,
            cast(WriteHandler) (&this.mem.write_be_u64) .funcptr,
            cast(HleHandler)   (&this.hle_handler)      .funcptr,
            cast(void*) this.mem,
            cast(void*) this
        ), mem, ringbuffer_size);
    }

    public void reset() {
        for (int i = 0; i < 32; i++) {
            state.gprs[i] = 0;
        }

        state.cr     = 0;
        state.xer    = 0;
        state.ctr    = 0;
        state.msr    = 0x00002032;
        state.hid0   = 0;
        state.hid2   = 0xE0000000;
        state.hid4   = 0;
        state.srr0   = 0;
        state.srr1   = 0;
        state.fpsr   = 0;
        state.fpscr  = 0;
        state.l2cr   = 0;
        state.mmcr0  = 0;
        state.mmcr1  = 0;
        state.pmc1   = 0;
        state.pmc2   = 0;
        state.pmc3   = 0;
        state.pmc4   = 0;
        state.tbu    = 0;
        state.tbl    = 0;
        state.sprg0  = 0;

        state.pc     = 0;
        state.lr     = 0;

        state.halted = false;
    }

    int num_log = 0;
    bool idle = false;
    bool exception_raised = false;
    bool shitter = false;
    int cunt = 0;

    bool is_sussy(u64 foat) {
        return (foat & 0x0000_ffff_ffff_0000) == 0x0000_0000_7fff_0000 || foat == 0x4330000000000000;
    }

    void sussy_floats() {
        for (int i = 0; i < 32; i++) {
            if (is_sussy(state.ps[i].ps0) || is_sussy(state.ps[i].ps1)) {
                log_function("BIG CHANGE: %x %x\n", mem.read_be_u32(state.pc - 4), 0);
                // log_state(&state);
                error_function("sussy float!\n");
            }
        }
    }

    bool had_17 = false;
    public void cycle(u32 num_cycles) {
        if (state.halted) {
            log_function("CPU is halted, not running\n");
        }
        
        u32 elapsed = 0;
        while (elapsed < num_cycles) {
            exception_raised = false;
            u32 old_pc = state.pc;
            if (state.pc >= 0x802778d4 && state.pc <= 0x80277930) {
                // log_broadway("PSMTXIdentity(%08x)", state.gprs[3]);
                // log_state(&state);
            }

            bool has_17 = false;
            for (int gpr = 0; gpr < 32; gpr++) {
                if (state.gprs[gpr] == 0x80297f70) {
                    has_17 = true;
                }
            }

            if (!had_17 && has_17) {
                log_broadway("HAD 17: %x %x", state.pc, state.gprs[1]);
            }

            had_17 = has_17;

            
            // if (state.pc == 0x802a4990) {
            //     log_broadway(" bta_hh_maint_dev_act");
            // }

            // if (state.pc == 0x802a5440) {
            //     log_broadway(" bta2_hh_maint_dev_act");
            // }

            // if (state.pc == 0x802da304) {
            //     log_broadway("BTA_DmAddDevice");
            // }

            // if (state.pc == 0x802da1ac) {
            //     log_broadway("WUD Init sub");
            // }


            // if (state.pc == 0x802da284) {
            //     log_broadway("WUD Init sub inenr poop: %x %x", state.gprs[0], state.gprs[31] + 0x13d);
            // }


            // if (state.pc == 0x802d8f0c) {
            //     log_broadway("PopulateDevices()");
            // }

            if (state.pc == 0x80297fd0) {
                log_broadway("stage: %x %x", state.gprs[3], state.gprs[5]);
            }


            if (state.pc == 0x80297f70) {
                log_broadway("stagist: %x %x", state.gprs[3], state.gprs[4]);
            }

            if (state.pc == 0x8027fa7c) {
                log_broadway("reading disker: %x %x", state.gprs[6], state.gprs[5]);
            }

            if (state.pc >= 0x8027fa14 &&  state.pc <= 0x8027fb74) {
                log_broadway("reading diskeyr: %x",state.pc);
            }


            // if (state.pc == 0x802a5794) {
            //     log_broadway(" bta4_hh_maint_dev_act");
            // }


            // if (state.pc == 0x802a0200) {
            //     log_broadway("bta_sys_event(%x)", mem.read_be_u16(state.gprs[3]));
            // }

            // if (state.pc == 0x8029ca64) {
            //     if (state.gprs[3] != 0)
            //     log_broadway("mbox addr -> %x %x",state.gprs[3], mem.read_be_u16(state.gprs[3]));

            // }

            // if (state.pc == 0x8029c7fc) {
            //     log_broadway("GKI_send_msg(%x, %x, %x (%x))", state.gprs[3], state.gprs[4], state.gprs[5], mem.read_be_u16(state.gprs[5]));
            //     if (mem.read_be_u16(state.gprs[5]) == 0x170e) {
            //         dump_stack();
            //     }
            // }

if (state.pc == 0x80295ddc) {
    
    log_function("FUNCTION: IOS_WriteAsync %x", state.lr);
    dump_stack();
}
if (state.pc == 0x80295edc) log_function("FUNCTION: IOS_Write %x", state.lr);
if (state.pc == 0x8028923c) log_broadway("ABOUT TO CALL RESUME");
if (state.pc == 0x8027fa14) log_broadway("disk_fun(%x, %x) from %x", state.gprs[3], mem.read_be_u32(0x8056dce0), state.lr);
if (state.pc >= 0x8028906c && state.pc <= 0x8028949c) log_broadway("dspmailchcekcer @ %x", state.pc);

if (state.pc == 0x802d3368) log_broadway("WPAD WIIMOTE hid parser: 0x%08x", state.ctr);
if (state.pc == 0x802d3300) log_broadway("WPAD WIIMOTE hid parser");
if (state.pc == 0x80286a64) log_broadway("AXRmtGetSamples");
if (state.pc == 0x80286a38) log_broadway("AXRmtGetSamplesLeft");
if (state.pc == 0x8028491c) log_broadway("__AID");
if (state.pc == 0x80284994) log_broadway("__AID %x", state.ctr);
if (state.pc >= 0x8028491c && state.pc <= 0x802849c0) log_broadway("__AID @ %x", state.pc);
if (state.pc == 0x80286394) log_broadway("__AID2");
if (state.pc == 0x8027f554) log_broadway("DVDLowRead");
if (state.pc == 0x8027e194) log_broadway("doTranslationCallback(%x %x)", state.gprs[3], state.gprs[4]);
// if (state.pc == 0x802af28c) log_broadway("FUNCTION: btm_sec_disconnect");
// if (state.pc == 0x802b1ca4) log_broadway("FUNCTION: gap_disconnect_ind");
// if (state.pc == 0x802b27a4) log_broadway("FUNCTION: btsnd_hcic_inq_cancel");
// if (state.pc == 0x802b2804) log_broadway("FUNCTION: btsnd_hcic_per_inq_mode");
// if (state.pc == 0x802b28c4) log_broadway("FUNCTION: btsnd_hcic_create_conn");
// if (state.pc == 0x802b29a4) log_broadway("FUNCTION: btsnd_hcic_disconnect");
// if (state.pc == 0x802b2a2c) log_broadway("FUNCTION: btsnd_hcic_add_SCO_conn");
// if (state.pc == 0x802b2ab8) log_broadway("FUNCTION: btsnd_hcic_accept_conn");
// if (state.pc == 0x802b2b18) log_broadway("FUNCTION: btsnd_hcic_reject_conn");
// if (state.pc == 0x802b2d14) log_broadway("FUNCTION: btsnd_hcic_link_key_neg_reply");
// if (state.pc == 0x802b2db4) log_broadway("FUNCTION: btsnd_hcic_pin_code_req_reply");
// if (state.pc == 0x802b2f98) log_broadway("FUNCTION: btsnd_hcic_pin_code_neg_reply");
// if (state.pc == 0x802b3038) log_broadway("FUNCTION: btsnd_hcic_change_conn_type");
// if (state.pc == 0x802b30c8) log_broadway("FUNCTION: btsnd_hcic_auth_request");
// if (state.pc == 0x802b3144) log_broadway("FUNCTION: btsnd_hcic_set_conn_encrypt");
// if (state.pc == 0x802b31d0) log_broadway("FUNCTION: btsnd_hcic_rmt_name_req");
// if (state.pc == 0x802b32a8) log_broadway("FUNCTION: btsnd_hcic_rmt_name_req_cancel");
// if (state.pc == 0x802b3348) log_broadway("FUNCTION: btsnd_hcic_rmt_features_req");
// if (state.pc == 0x802b33c4) log_broadway("FUNCTION: btsnd_hcic_rmt_ver_req");
// if (state.pc == 0x802b3440) log_broadway("FUNCTION: btsnd_hcic_read_rmt_clk_offset");
// if (state.pc == 0x802b34bc) log_broadway("FUNCTION: btsnd_hcic_setup_esco_conn");
// if (state.pc == 0x802b35b8) log_broadway("FUNCTION: btsnd_hcic_accept_esco_conn");
// if (state.pc == 0x802b36a0) log_broadway("FUNCTION: btsnd_hcic_reject_esco_conn");
// if (state.pc == 0x802b3700) log_broadway("FUNCTION: btsnd_hcic_hold_mode");
// if (state.pc == 0x802b37b4) log_broadway("FUNCTION: btsnd_hcic_sniff_mode");
// if (state.pc == 0x802b3880) log_broadway("FUNCTION: btsnd_hcic_exit_sniff_mode");
// if (state.pc == 0x802b3904) log_broadway("FUNCTION: btsnd_hcic_park_mode");
// if (state.pc == 0x802b39b8) log_broadway("FUNCTION: btsnd_hcic_exit_park_mode");
// if (state.pc == 0x802b3a3c) log_broadway("FUNCTION: btsnd_hcic_switch_role");
// if (state.pc == 0x802b3aec) log_broadway("FUNCTION: btsnd_hcic_write_policy_set");
// if (state.pc == 0x802b3b80) log_broadway("FUNCTION: btsnd_hcic_reset");
// if (state.pc == 0x802b3bdc) log_broadway("FUNCTION: btsnd_hcic_set_event_filter");
// if (state.pc == 0x802b3d98) log_broadway("FUNCTION: btsnd_hcic_write_pin_type");
// if (state.pc == 0x802b3e0c) log_broadway("FUNCTION: btsnd_hcic_read_stored_key");
// if (state.pc == 0x802b3e6c) log_broadway("FUNCTION: btsnd_hcic_write_stored_key");
// if (state.pc == 0x802b402c) log_broadway("FUNCTION: btsnd_hcic_delete_stored_key");
// if (state.pc == 0x802b40dc) log_broadway("FUNCTION: btsnd_hcic_change_name");
// if (state.pc == 0x802b421c) log_broadway("FUNCTION: btsnd_hcic_write_page_tout");
// if (state.pc == 0x802b4254) log_broadway("FUNCTION: btsnd_hcic_write_scan_enable");
// if (state.pc == 0x802b4284) log_broadway("FUNCTION: btsnd_hcic_write_pagescan_cfg");
// if (state.pc == 0x802b42c8) log_broadway("FUNCTION: btsnd_hcic_write_inqscan_cfg");
// if (state.pc == 0x802b430c) log_broadway("FUNCTION: btsnd_hcic_write_auth_enable");
// if (state.pc == 0x802b4380) log_broadway("FUNCTION: btsnd_hcic_write_encr_mode");
// if (state.pc == 0x802b43f4) log_broadway("FUNCTION: btsnd_hcic_write_dev_class");
// if (state.pc == 0x802b4438) log_broadway("FUNCTION: btsnd_hcic_write_auto_flush_tout");
// if (state.pc == 0x802b447c) log_broadway("FUNCTION: btsnd_hcic_set_host_buf_size");
// if (state.pc == 0x802b4538) log_broadway("FUNCTION: btsnd_hcic_write_link_super_tout");
// if (state.pc == 0x802b45cc) log_broadway("FUNCTION: btsnd_hcic_write_cur_iac_lap");
// if (state.pc == 0x802b463c) log_broadway("FUNCTION: btsnd_hcic_read_local_ver");
// if (state.pc == 0x802b469c) log_broadway("FUNCTION: btsnd_hcic_read_local_features");
// if (state.pc == 0x802b46f8) log_broadway("FUNCTION: btsnd_hcic_read_buffer_size");
// if (state.pc == 0x802b4720) log_broadway("FUNCTION: btsnd_hcic_read_bd_addr");
// if (state.pc == 0x802b4780) log_broadway("FUNCTION: btsnd_hcic_get_link_quality");
// if (state.pc == 0x802b47fc) log_broadway("FUNCTION: btsnd_hcic_read_rssi");
// if (state.pc == 0x802b4874) log_broadway("FUNCTION: btsnd_hcic_set_afh_channels");
// if (state.pc == 0x802b4c94) log_broadway("FUNCTION: btsnd_hcic_write_inqscan_type");
// if (state.pc == 0x802b4cc4) log_broadway("FUNCTION: btsnd_hcic_write_inquiry_mode");
// if (state.pc == 0x802b4cf4) log_broadway("FUNCTION: btsnd_hcic_write_pagescan_type");
// if (state.pc == 0x802b4d24) log_broadway("FUNCTION: btsnd_hcic_vendor_spec_cmd");
// if (state.pc == 0x802b625c) log_broadway("FUNCTION: hidh_conn_disconnect");
// if (state.pc == 0x802b72e4) log_broadway("FUNCTION: hidh_l2cif_disconnect_ind");
// if (state.pc == 0x802b75a8) log_broadway("FUNCTION: hidh_l2cif_disconnect_cfm");
// if (state.pc == 0x802b88bc) log_broadway("FUNCTION: L2CA_DisconnectReq");
// if (state.pc == 0x802b8960) log_broadway("FUNCTION: L2CA_DisconnectRsp");
// if (state.pc == 0x802b9d08) log_broadway("FUNCTION: l2c_csm_w4_l2cap_disconnect_rsp");
// if (state.pc == 0x802b9eec) log_broadway("FUNCTION: l2c_csm_w4_l2ca_disconnect_rsp");
// if (state.pc == 0x802be184) log_broadway("FUNCTION: l2cu_lcb_disconnecting");
// if (state.pc == 0x802c00b0) log_broadway("FUNCTION: RFCOMM_DisconnectInd");
// if (state.pc == 0x802c7b54) log_broadway("FUNCTION: sdp_disconnect_ind");
// if (state.pc == 0x802c7ed0) log_broadway("FUNCTION: sdp_disconnect_cfm");
// if (state.pc == 0x802b85a4) { log_broadway("FUNCTION: L2CA_ConnectRsp"); dump_stack(); }
// if (state.pc == 0x802b8370) log_broadway("FUNCTION: L2CA_ConnectReq");
// if (state.pc >= 0x802ce2fc && state.pc <= 0x802ce324) log_broadway("FUNCTION: WPADSetConnectCallback(%x)", state.pc); 

if (state.pc == 0x802973a0) { log_broadway("ios_dipshit(%08x)", state.gprs[3]); }
if (state.pc == 0x802ce2fc) { log_broadway("FUNCTION: WPADSetConnectCallback(%x)", state.gprs[3]); 
dump_stack();}
if (state.pc == 0x8001d9a0)  log_broadway("FUNCTION: Func7(%x)", state.gprs[3]); 
if (state.pc == 0x8026c8e8) log_broadway("FUNCTION: InsertAlarm");
if (state.pc == 0x8026cb38) log_broadway("FUNCTION: OSSetAlarm(%x)", state.gprs[3]);
if (state.pc == 0x8026cba8) log_broadway("FUNCTION: OSSetPeriodicAlarm");
if (state.pc == 0x8026cc2c) log_broadway("FUNCTION: OSCancelAlarm(%x)", state.gprs[3]);
if (state.pc == 0x80006124)  log_broadway("FUNCTION: Func8(%x)", state.gprs[3]); 
if (state.pc == 0x80304edc)  log_broadway("FUNCTION: Func4(%x)", state.gprs[3]); 
if (state.pc == 0x80235ce0)  log_broadway("FUNCTION: Func5(%x)", state.gprs[3]); 
if (state.pc == 0x801a71a4)  log_broadway("FUNCTION: Func6(%x)", state.gprs[3]); 
if (state.pc == 0x802cee08)  log_broadway("FUNCTION: Func1(%x)", state.gprs[3]); 
if (state.pc == 0x802fbe5c)  log_broadway("FUNCTION: Func2(%x)", state.gprs[3]); 
if (state.pc == 0x802fc730)  log_broadway("FUNCTION: Func3(%x)", state.gprs[3]); 
if (state.pc == 0x802cd3a0) log_broadway("FUNCTION: WPAD thisq(%x %x)", state.gprs[0], state.gprs[29] + 0x161); 
if (state.pc == 0x802cda9c) log_broadway("FUNCTION: WPADiRetrieveChannel");
if (state.pc == 0x802cdfe0) log_broadway("FUNCTION: WPADiRecvCallback");
if (state.pc == 0x802ce7b8) log_broadway("FUNCTION: WPADSaveConfig");
if (state.pc == 0x802d0458) log_broadway("FUNCTION: WPADSetSpeakerVolume");
if (state.pc == 0x802d1da8) log_broadway("FUNCTION: WPADiSendWriteDataCmd");
if (state.pc == 0x802d1f5c) log_broadway("FUNCTION: WPADiSendWriteData");
if (state.pc == 0x802d2114) log_broadway("FUNCTION: WPADiSendReadData");
if (state.pc == 0x802d22c0) log_broadway("FUNCTION: WPADiClearQueue");
if (state.pc == 0x802d3300) log_broadway("FUNCTION: WPADiHIDParser");
if (state.pc == 0x802fc694) log_broadway("FUNCTION: Setup__Q44nw4r3snd6detail20RemoteSpeakerManagerFv(%x)", state.gprs[3]);
if (state.pc == 0x802890b8) log_broadway("FUNCTION: MAILBOX: %x", state.gprs[3]);
if (state.pc == 0x802d2114) {
    log_broadway("FUNCTION: WPADiSendReadData");
}
if (state.pc == 0x802deefc) {
    log_broadway("FUNCTION: WPADInit() returned");
}
if (state.pc == 0x802d2209) {
    log_broadway("FUNCTION: WPAD->queue_size = %x (%x)", state.gprs[0], state.gprs[30] + 1);
}
if (state.pc == 0x802d7b14) {
    log_broadway("FUNCTION: WIIMOTE DEJBIT %x", state.lr);

            hle_os_report2(cast(void*) &mem, &state);
}


        if (state.pc  >= 0x8028b21c && state.pc  <= 0x8028b318) {
            log_broadway("__GXSaveFifo: %x", state.pc);
        }
if (state.pc == 0x802df108) log_broadway("FUNCTION: WPADInit caller returned %x", state.lr);
if (state.pc == 0x8019d5b0) error_broadway("iNFINITE LOOP: %08x", state.lr);
if (state.pc == 0x8019b6c8) error_broadway("ASSERT FAILED: %08x", state.lr);
if (state.pc >= 0x802913ac && state.pc <= 0x80291454) log_broadway("ASSERT FAILED: %08x", state.pc);

            // log_jit("At pc: %x", old_pc);
            // log_state(&state);
            JitReturnValue jit_return_value = jit.run(&state);
            auto delta = jit_return_value.num_instructions_executed * 2;
            
            if (state.pc == 0x8029423c) {
                // log_broadway("FUNCTION: ISFS_ReadDirAsync");
                // dump_stack();
            }
            if (state.pc == 0x802998f0) {
                // log_broadway("FUNCTION: nand2");
                // dump_stack();
            }
            if (state.pc == 0x802cdadc) {

                // dump_stack();
            }

            if (jit_return_value.block_return_value == BlockReturnValue.DecrementerChanged) {
                scheduler.remove_event(decrementer_event);
                decrementer_event = scheduler.add_event_relative_to_clock(() => raise_exception(ExceptionType.Decrementer), state.dec);
            } else if (jit_return_value.block_return_value == BlockReturnValue.CpuHalted) {
                auto fast_forward = scheduler.tick_to_next_event();
                scheduler.process_events();
                elapsed += fast_forward;

                if (elapsed < num_cycles) {
                    handle_pending_interrupts();
                    return;
                } else {
                    continue;
                }
            }

            state.dec -= delta;

            scheduler.tick(delta);
            scheduler.process_events();

            // todo: yeet this to the scheduler
            u64 time_base = cast(u64) state.tbu << 32 | cast(u64) state.tbl;
            time_base += delta;
            state.tbu = cast(u32) (time_base >> 32);
            state.tbl = cast(u32) time_base;

            if (state.pc == 0) {
                error_jit("PC is zero, %x", old_pc);
            }
        
            handle_pending_interrupts();
            elapsed += delta;
        }

        // log_function("decrementer: %x %x", state.dec, state.dar);
    }

    // TODO: do single stepping properly
    public void single_step() {
        cycle(1);
    }

    public void run_until_return() {
        assert(this.state.pc != 0xDEADBEEF);

        this.state.lr = 0xDEADBEEF;

        while (this.state.pc != 0xDEADBEEF) {
            cycle(1);
        }
    }

    public HleContext* get_hle_context() {
        return &this.hle_context;
    }

    private void hle_handler(int function_id) {
        this.hle_context.hle_handler(&this.state, function_id);
        this.state.pc = this.state.lr;
    }

    public void on_error() {
        log_function("ERROR DETECTED");
        log_state(&state);
        dump_stack();
        jit.on_error();

        import util.dump;
        dump(this.mem.mem1, "mem1.bin");
        dump(this.mem.mem2, "mem2.bin");
    }

    // here are the really annoying-to-write functions:

    public void set_gpr(int gpr, u32 value) {
        this.state.gprs[gpr] = value;
    }

    public u32 get_gpr(int gpr) {
        return this.state.gprs[gpr];
    }

    public void set_gqr(int gqr, u32 value) {
        this.state.gqrs[gqr] = value;
    }

    public u32 get_gqr(int gqr) {
        return this.state.gqrs[gqr];
    }

    public void set_cr(int cr, u32 value) {
        this.state.cr = (this.state.cr & ~(0xF << (cr * 4))) | (value << (cr * 4));
    }

    public u32 get_cr(int cr) {
        return (this.state.cr >> (cr * 4)) & 0xF;
    }

    public void set_xer(u32 value) {
        this.state.xer = value;
    }

    public u32 get_xer() {
        return this.state.xer;
    }

    public void set_ctr(u32 value) {
        this.state.ctr = value;
    }

    public u32 get_ctr() {
        return this.state.ctr;
    }

    public void set_msr(u32 value) {
        this.state.msr = value;
    }

    public u32 get_msr() {
        return this.state.msr;
    }

    public void set_hid0(u32 value) {
        this.state.hid0 = value;
    }

    public u32 get_hid0() {
        return this.state.hid0;
    }

    public void set_hid2(u32 value) {
        this.state.hid2 = value;
    }

    public u32 get_hid2() {
        return this.state.hid2;
    }

    public void set_lr(u32 lr) {
        state.lr = lr;
    }

    public u32 get_lr() {
        return state.lr;
    }

    public void set_pc(u32 pc) {
        state.pc = pc;
    }

    public u32 get_pc() {
        return state.pc;
    }

    public InterruptController get_interrupt_controller() {
        return this.interrupt_controller;
    }

    // SRR1[0,5-9,16-23,25-27,30-31]
    void handle_exception(ExceptionType type) {
        log_interrupt("Exception: %s. Pending: %x", type, pending_interrupts);
        if (exception_raised) error_jit("Exception already raised");
        exception_raised = true;

        assert(type == ExceptionType.Decrementer || type == ExceptionType.ExternalInterrupt);

        state.srr0 = state.pc;
        state.srr1 &= ~(0b0000_0111_1100_0000_1111_1111_1111_1111);
        state.srr1 |= state.msr & (0b0000_0111_1100_0000_1111_1111_1111_1111);

        // clear IR and DR
        state.msr &= ~(1 << 4 | 1 << 5);

        // clear RI
        state.msr &= ~(1 << 30);

        // this exception *is* recoverable
        state.srr1 |= (1 << 30);

        // clear POW, EE, PR, FP, FE0, SE, BE, FE1, PM
        state.msr &= ~(0b0000_0000_0000_0100_1110_1111_0000_0000);

        // copy ILE to LE
        state.msr |= state.msr.bit(16);

        bool ip = state.msr.bit(6);
        u32 base = ip ? 0xFFF0_0000 : 0x0000_0000;

        switch (type) {
        case ExceptionType.ExternalInterrupt: state.pc = base + 0x500; break;
        case ExceptionType.Decrementer:       state.pc = base + 0x900; break;
        default: assert(0);
        }
    }

    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    void connect_ipc(IPC ipc) {
        this.interrupt_controller.connect_ipc(ipc);
    }

    int pending_interrupts = 0;
    void handle_pending_interrupts() {
        log_interrupt("Pending interrupts: %x (%x)", pending_interrupts, state.msr.bit(15));
        if (pending_interrupts > 0) {
            if (state.msr.bit(15)) {
                log_interrupt("Handling pending interrupt: %x", pending_interrupts);
                auto exception_to_raise = core.bitop.bsf(pending_interrupts);
                // log_function("Raising exception: %s", exception_to_raise);
                handle_exception(cast(ExceptionType) exception_to_raise);
                pending_interrupts &= ~(1 << exception_to_raise);
            } else {
                // interrupt_controller.maybe_raise_processor_interface_interrupt();
            }
        }
    }

    void raise_exception(ExceptionType type) {
        log_interrupt("Raise exception: %s %d", type, state.msr.bit(15));
        pending_interrupts |= (1 << type);
    }

    void set_exception(ExceptionType type, bool value) {
        if (value) {
            pending_interrupts |= (1 << type);
        } else {
            pending_interrupts &= ~(1 << type);
        }
    }

    void dump_stack() {
        log_broadway("Dumping stack. pc: %x lr: %x", state.pc, state.lr);
        for (int i = 0; i < 500; i++) {
            log_broadway("stack[%x] = 0x%08x", i, mem.read_be_u32(state.gprs[1] + i * 4));
        }
    }
}
 