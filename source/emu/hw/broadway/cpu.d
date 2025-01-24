module emu.hw.broadway.cpu;

import core.bitop;
import emu.hw.broadway.exception_type;
import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.broadway.state;
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

    public void cycle(u32 num_cycles) {
        if (state.halted) {
            log_function("CPU is halted, not running\n");
        }

        
        u32 elapsed = 0;
        while (elapsed < num_cycles && !state.halted) {
            exception_raised = false;
            u32 old_pc = state.pc;
            
            if (state.pc == 0x801a1018) {
                log_hollywood("magic shithole: %x", state.gprs[3]);
            }
if (state.pc == 0x8027cfec) log_hollywood("FUNCTION: DVDInquiryAsync");
// if (state.pc == 0x8027d18c) log_function("FUNCTION: DVDGetDriveStatus");
if (state.pc == 0x8027d238) log_hollywood("FUNCTION: DVDResume");
if (state.pc == 0x8027d6b8) log_hollywood("FUNCTION: __DVDGetCoverStatus");
if (state.pc == 0x8027d780) log_hollywood("FUNCTION: __DVDPrepareResetAsync");
if (state.pc == 0x8027d8a8) log_hollywood("FUNCTION: __DVDPrepareReset");
if (state.pc == 0x8027d9dc) log_hollywood("FUNCTION: __DVDTestAlarm");
if (state.pc == 0x8027da40) log_hollywood("FUNCTION: __DVDPushWaitingQueue");
if (state.pc == 0x8027daa8) log_hollywood("FUNCTION: __DVDPopWaitingQueue");
if (state.pc == 0x8027db48) log_hollywood("FUNCTION: __DVDCheckWaitingQueue");
if (state.pc == 0x8027dba0) log_hollywood("FUNCTION: __DVDGetNextWaitingQueue");
if (state.pc == 0x8027dc00) log_hollywood("FUNCTION: __DVDDequeueWaitingQueue");
            auto delta = jit.run(&state);

            if (state.pc != old_pc + 4 && false) {
                if (state.pc == 0x80034afc) log_function("FUNCTION: __opPA4_Cf__Q34nw4r4math5MTX34CFv");
if (state.pc == 0x8005f924) log_function("FUNCTION: SetMainSend__Q34nw4r3snd11SoundPlayerFf");
if (state.pc == 0x800954dc) log_function("FUNCTION: GXInitLightAttnA");
if (state.pc == 0x800954f0) log_function("FUNCTION: GXGetLightAttnA");
if (state.pc == 0x80099dfc) log_function("FUNCTION: SetMaxBiquadFilterValue__Q34nw4r3snd15Sound3DListenerFf");
if (state.pc == 0x8009f0f4) log_function("FUNCTION: SetPitch__Q44nw4r3snd6detail8SeqTrackFf");
if (state.pc == 0x800d9dbc) log_function("FUNCTION: setFadeColorEnable__Q310homebutton10HomeButton10BlackFaderFb");
if (state.pc == 0x80104584) log_function("FUNCTION: SetPan__Q44nw4r3snd6detail10BasicSoundFf");
if (state.pc == 0x8011e928) log_function("FUNCTION: NHTTPi_IsCreateCommThreadMessageQueue");
if (state.pc == 0x80131b94) log_function("FUNCTION: __as__Q34nw4r4math4VEC3FRCQ34nw4r4math4VEC3");
if (state.pc == 0x80148294) log_function("FUNCTION: GetIntPtr__Q34nw4r2ut32@unnamed@ut_ArchiveFontBase_cpp@FPCv");
if (state.pc == 0x8014ca88) log_function("FUNCTION: VFiPFVOL_errnum");
if (state.pc == 0x8014e4b4) log_function("FUNCTION: GetName__Q36nw4hbm3lyt4PaneCFv");
if (state.pc == 0x8017aba8) log_function("FUNCTION: __dt__Q36nw4hbm3lyt19ArcResourceAccessorFv");
if (state.pc == 0x8019f868) log_function("FUNCTION: SetVolume__Q44nw4r3snd6detail8SeqTrackFf");
if (state.pc == 0x801d2e80) log_function("FUNCTION: UpdateReadWritePoint___Q44nw4r3mcs6detail14Hio2RingBufferFv");
if (state.pc == 0x801e6258) log_function("FUNCTION: ptr__Q34nw4r3g3d34ResCommon<Q34nw4r3g3d10ResDicData>CFv");
if (state.pc == 0x8023365c) log_function("FUNCTION: __as__Q34nw4r3g3d35ResCommon<Q34nw4r3g3d11ResNodeData>FRCQ34nw4r3g3d35ResCommon<Q34nw4r3g3d11ResNodeData>");
if (state.pc == 0x80239e88) log_function("FUNCTION: __dt__Q34nw4r3snd11SoundHandleFv");
if (state.pc == 0x8023abe8) log_function("FUNCTION: DBIsDebuggerPresent");
if (state.pc == 0x8023fa28) log_function("FUNCTION: GetSurroundPan__Q44nw4r3snd6detail11BasicPlayerCFv");
if (state.pc == 0x80252404) log_function("FUNCTION: gt2SetConnectionData");
if (state.pc == 0x80267564) log_function("FUNCTION: __DBIntrHandler");
if (state.pc == 0x80267588) log_function("FUNCTION: DBInitComm");
if (state.pc == 0x802675e4) log_function("FUNCTION: DBInitInterrupts");
if (state.pc == 0x80267638) log_function("FUNCTION: DBQueryData");
if (state.pc == 0x802676dc) log_function("FUNCTION: DBRead");
if (state.pc == 0x80267b5c) log_function("FUNCTION: __DBEXIInit");
if (state.pc == 0x80267c18) log_function("FUNCTION: __DBEXIReadReg");
if (state.pc == 0x80267d3c) log_function("FUNCTION: __DBEXIWriteReg");
if (state.pc == 0x80267e40) log_function("FUNCTION: __DBEXIReadRam");
if (state.pc == 0x802680f0) log_function("FUNCTION: EXIImm");
if (state.pc == 0x8026836c) log_function("FUNCTION: EXIImmEx");
if (state.pc == 0x80268410) log_function("FUNCTION: EXIDma");
if (state.pc == 0x80268508) log_function("FUNCTION: EXISync");
if (state.pc == 0x80268784) log_function("FUNCTION: EXISetExiCallback");
if (state.pc == 0x80268808) log_function("FUNCTION: __EXIProbe");
if (state.pc == 0x80268988) log_function("FUNCTION: EXIAttach");
if (state.pc == 0x80268aa0) log_function("FUNCTION: EXIDetach");
if (state.pc == 0x80268b58) log_function("FUNCTION: EXISelect");
if (state.pc == 0x80268c88) log_function("FUNCTION: EXIDeselect");
if (state.pc == 0x80268d88) log_function("FUNCTION: EXIIntrruptHandler");
if (state.pc == 0x80268e40) log_function("FUNCTION: TCIntrruptHandler");
if (state.pc == 0x80269058) log_function("FUNCTION: EXTIntrruptHandler");
if (state.pc == 0x80269128) log_function("FUNCTION: EXIInit");
if (state.pc == 0x802692ec) log_function("FUNCTION: EXILock");
if (state.pc == 0x802693e8) log_function("FUNCTION: EXIUnlock");
if (state.pc == 0x802694c0) log_function("FUNCTION: UnlockedHandler");
if (state.pc == 0x802694e8) log_function("FUNCTION: EXIGetID");
if (state.pc == 0x80269bc8) log_function("FUNCTION: EXIWriteReg");
if (state.pc == 0x80269d58) log_function("FUNCTION: IsStatsConnected");
if (state.pc == 0x80269d70) log_function("FUNCTION: CompleteTransfer");
if (state.pc == 0x8026a064) log_function("FUNCTION: SIInterruptHandler");
if (state.pc == 0x8026a450) log_function("FUNCTION: SIEnablePollingInterrupt");
if (state.pc == 0x8026a4c8) log_function("FUNCTION: SIUnregisterPollingHandler");
if (state.pc == 0x8026a5b0) log_function("FUNCTION: SIInit");
if (state.pc == 0x8026a670) log_function("FUNCTION: __SITransfer");
if (state.pc == 0x8026a820) log_function("FUNCTION: SISetCommand");
if (state.pc == 0x8026a834) log_function("FUNCTION: SISetXY");
if (state.pc == 0x8026a890) log_function("FUNCTION: SIEnablePolling");
if (state.pc == 0x8026a918) log_function("FUNCTION: SIDisablePolling");
if (state.pc == 0x8026a984) log_function("FUNCTION: SIGetResponse");
if (state.pc == 0x8026aaa8) log_function("FUNCTION: AlarmHandler");
if (state.pc == 0x8026ab34) log_function("FUNCTION: SITransfer");
if (state.pc == 0x8026aca0) log_function("FUNCTION: GetTypeCallback");
if (state.pc == 0x8026af50) log_function("FUNCTION: SIGetType");
if (state.pc == 0x8026b104) log_function("FUNCTION: SIGetTypeAsync");
if (state.pc == 0x8026b304) log_function("FUNCTION: PPCMfhid0");
if (state.pc == 0x8026b314) log_function("FUNCTION: PPCMfl2cr");
if (state.pc == 0x8026b31c) log_function("FUNCTION: PPCMtl2cr");
if (state.pc == 0x8026b324) log_function("FUNCTION: PPCMtdec");
if (state.pc == 0x8026b334) log_function("FUNCTION: PPCHalt");
if (state.pc == 0x8026b348) log_function("FUNCTION: PPCMtmmcr0");
if (state.pc == 0x8026b350) log_function("FUNCTION: PPCMtmmcr1");
if (state.pc == 0x8026b358) log_function("FUNCTION: PPCMtpmc1");
if (state.pc == 0x8026b360) log_function("FUNCTION: PPCMtpmc2");
if (state.pc == 0x8026b368) log_function("FUNCTION: PPCMtpmc3");
if (state.pc == 0x8026b370) log_function("FUNCTION: PPCMtpmc4");
if (state.pc == 0x8026b378) log_function("FUNCTION: PPCMffpscr");
if (state.pc == 0x8026b398) log_function("FUNCTION: PPCMtfpscr");
if (state.pc == 0x8026b3c0) log_function("FUNCTION: PPCMfhid2");
if (state.pc == 0x8026b3c8) log_function("FUNCTION: PPCMthid2");
if (state.pc == 0x8026b3d0) log_function("FUNCTION: PPCMfwpar");
if (state.pc == 0x8026b3dc) log_function("FUNCTION: PPCMtwpar");
if (state.pc == 0x8026b3e4) log_function("FUNCTION: PPCDisableSpeculation");
if (state.pc == 0x8026b40c) log_function("FUNCTION: PPCSetFpNonIEEEMode");
if (state.pc == 0x8026b48c) log_function("FUNCTION: __DBExceptionDestinationAux");
if (state.pc == 0x8026b4d4) log_function("FUNCTION: __DBExceptionDestination");
if (state.pc == 0x8026b4e4) log_function("FUNCTION: __DBIsExceptionMarked");
 if (state.pc == 0x8026b54c) log_function("FUNCTION: __OSFPRInit");
 if (state.pc == 0x8026b674) log_function("FUNCTION: __OSGetIOSRev");
if (state.pc == 0x8026b950) log_function("FUNCTION: ClearArena");
if (state.pc == 0x8026bb2c) log_function("FUNCTION: ClearMEM2Arena");
if (state.pc == 0x8026bd10) log_function("FUNCTION: InquiryCallback");
 if (state.pc == 0x8026c3e0) log_function("FUNCTION: OSExceptionInit");
 if (state.pc == 0x8026c688) log_function("FUNCTION: __OSSetExceptionHandler");
 if (state.pc == 0x8026c69c) log_function("FUNCTION: __OSGetExceptionHandler");
 if (state.pc == 0x8026c6ac) log_function("FUNCTION: OSExceptionVector");
 if (state.pc == 0x8026c748) log_function("FUNCTION: OSDefaultExceptionHandler");
 if (state.pc == 0x8026c7a0) log_function("FUNCTION: __OSPSInit");
 if (state.pc == 0x8026c7f4) log_function("FUNCTION: __OSGetDIConfig");
 if (state.pc == 0x8026c880) log_function("FUNCTION: __OSInitAlarm");
if (state.pc == 0x8026c8e8) log_function("FUNCTION: InsertAlarm");
 if (state.pc == 0x8026cb38) log_function("FUNCTION: OSSetAlarm");
 if (state.pc == 0x8026cba8) log_function("FUNCTION: OSSetPeriodicAlarm");
 if (state.pc == 0x8026cc2c) log_function("FUNCTION: OSCancelAlarm");
if (state.pc == 0x8026cd44) log_function("FUNCTION: DecrementerExceptionCallback");
if (state.pc == 0x8026cfc0) log_function("FUNCTION: OnReset");
if (state.pc == 0x8026d05c) log_function("FUNCTION: DLInsert");
 if (state.pc == 0x8026d200) log_function("FUNCTION: OSFreeToHeap");
if (state.pc == 0x8026d52c) log_function("FUNCTION: __OSInitAudioSystem");
if (state.pc == 0x8026d7c0) log_function("FUNCTION: DCEnable");
if (state.pc == 0x8026d7d4) log_function("FUNCTION: DCInvalidateRange");
if (state.pc == 0x8026d800) log_function("FUNCTION: DCFlushRange");
if (state.pc == 0x8026d830) log_function("FUNCTION: DCStoreRange");
if (state.pc == 0x8026d860) log_function("FUNCTION: DCFlushRangeNoSync");
if (state.pc == 0x8026d88c) log_function("FUNCTION: DCZeroRange");
if (state.pc == 0x8026d8b8) log_function("FUNCTION: ICInvalidateRange");
if (state.pc == 0x8026d8ec) log_function("FUNCTION: ICFlashInvalidate");
if (state.pc == 0x8026d8fc) log_function("FUNCTION: ICEnable");
if (state.pc == 0x8026d910) log_function("FUNCTION: LCDisable");
if (state.pc == 0x8026dbb8) log_function("FUNCTION: __OSLoadFPUContext");
if (state.pc == 0x8026dcdc) log_function("FUNCTION: __OSSaveFPUContext");
if (state.pc == 0x8026de0c) log_function("FUNCTION: OSSetCurrentContext");
if (state.pc == 0x8026de74) log_function("FUNCTION: OSSaveContext");
if (state.pc == 0x8026dee4) log_function("FUNCTION: ven_shutdown_cb");
if (state.pc == 0x8026def4) log_function("FUNCTION: OSLoadContext");
if (state.pc == 0x8026dfcc) log_function("FUNCTION: OSGetStackPointer");
if (state.pc == 0x8026dfd4) log_function("FUNCTION: OSSwitchFiber");
if (state.pc == 0x8026e004) { log_function("FUNCTION: OSSwitchFiberEx"); }
if (state.pc == 0x8026e034) log_function("FUNCTION: OSClearContext");
if (state.pc == 0x8026e058) log_function("FUNCTION: OSInitContext");
if (state.pc == 0x8026e114) log_function("FUNCTION: OSDumpContext");
if (state.pc == 0x8026e374) log_function("FUNCTION: OSSwitchFPUContext");
if (state.pc == 0x8026e4d0) log_function("FUNCTION: OSSetErrorHandler");
if (state.pc == 0x8026ebc8) log_function("FUNCTION: Run");
if (state.pc == 0x8026ec10) log_function("FUNCTION: __OSGetExecParams");
if (state.pc == 0x8026f9e8) log_function("FUNCTION: __OSBootDol");
if (state.pc == 0x8027009c) log_function("FUNCTION: ConfigureVideo");
if (state.pc == 0x80270ad0) log_function("FUNCTION: Decode");
if (state.pc == 0x80270b94) log_function("FUNCTION: ptr__Q34nw4r3g3d35ResCommon<Q34nw4r3g3d11ResNodeData>CFv");
if (state.pc == 0x80270c74) log_function("FUNCTION: OSGetFontEncode");
if (state.pc == 0x80270cc8) log_function("FUNCTION: OSSetFontEncode");
if (state.pc == 0x80270d48) log_function("FUNCTION: ReadFont");
if (state.pc == 0x80271048) log_function("FUNCTION: OSLoadFont");
if (state.pc == 0x80271170) log_function("FUNCTION: ParseStringS");
if (state.pc == 0x8027126c) log_function("FUNCTION: ParseStringW");
if (state.pc == 0x80271428) log_function("FUNCTION: OSGetFontTexel");
if (state.pc == 0x802716b8) log_function("FUNCTION: OSDisableInterrupts");
if (state.pc == 0x802716cc) log_function("FUNCTION: OSEnableInterrupts");
if (state.pc == 0x802716e0) log_function("FUNCTION: OSRestoreInterrupts");
if (state.pc == 0x80271718) log_function("FUNCTION: __OSGetInterruptHandler");
if (state.pc == 0x80271728) log_function("FUNCTION: __OSInterruptInit");
if (state.pc == 0x802717ec) log_function("FUNCTION: SetInterruptMask");
if (state.pc == 0x80271a48) log_function("FUNCTION: __OSMaskInterrupts");
if (state.pc == 0x80271ac8) log_function("FUNCTION: __OSUnmaskInterrupts");
if (state.pc == 0x80271b48) log_function("FUNCTION: __OSDispatchInterrupt");
if (state.pc == 0x802720ec) log_function("FUNCTION: Link");
if (state.pc == 0x802727c4) log_function("FUNCTION: __OSModuleInit");
if (state.pc == 0x8027283c) log_function("FUNCTION: OSSendMessage");
if (state.pc == 0x80272904) log_function("FUNCTION: OSReceiveMessage");
if (state.pc == 0x802729e0) log_function("FUNCTION: OSGetPhysicalMem1Size");
if (state.pc == 0x802729ec) log_function("FUNCTION: OSGetPhysicalMem2Size");
if (state.pc == 0x802729f8) log_function("FUNCTION: OSGetConsoleSimulatedMem1Size");
if (state.pc == 0x80272a04) log_function("FUNCTION: OSGetConsoleSimulatedMem2Size");
if (state.pc == 0x80272a4c) log_function("FUNCTION: MEMIntrruptHandler");
if (state.pc == 0x80272a94) log_function("FUNCTION: ConfigMEM1_24MB");
if (state.pc == 0x80272b14) log_function("FUNCTION: ConfigMEM1_48MB");
if (state.pc == 0x80272b94) log_function("FUNCTION: ConfigMEM2_52MB");
if (state.pc == 0x80272c74) log_function("FUNCTION: ConfigMEM2_56MB");
if (state.pc == 0x80272d54) log_function("FUNCTION: ConfigMEM2_64MB");
if (state.pc == 0x80272e00) log_function("FUNCTION: ConfigMEM2_112MB");
if (state.pc == 0x80272ee0) log_function("FUNCTION: ConfigMEM2_128MB");
if (state.pc == 0x80272f8c) log_function("FUNCTION: ConfigMEM_ES1_0");
if (state.pc == 0x80272ff4) log_function("FUNCTION: BATConfig");
if (state.pc == 0x8027322c) log_function("FUNCTION: OSLockMutex");
if (state.pc == 0x80273308) log_function("FUNCTION: OSUnlockMutex");
if (state.pc == 0x802733d0) log_function("FUNCTION: __OSUnlockAllMutex");
if (state.pc == 0x80273504) log_function("FUNCTION: GXSetVerifyLevel");
if (state.pc == 0x80273538) log_function("FUNCTION: __OSCallShutdownFunctions");
if (state.pc == 0x80273b08) log_function("FUNCTION: OSGetResetCode");
if (state.pc == 0x80273b54) log_function("FUNCTION: WriteSramCallback");
if (state.pc == 0x80273c8c) log_function("FUNCTION: __OSInitSram");
if (state.pc == 0x80273e8c) log_function("FUNCTION: UnlockSram");
if (state.pc == 0x8027417c) log_function("FUNCTION: __OSReadROM");
if (state.pc == 0x802742a0) log_function("FUNCTION: OSGetWirelessID");
if (state.pc == 0x80274318) log_function("FUNCTION: OSSetWirelessID");
if (state.pc == 0x802743b4) log_function("FUNCTION: __OSGetRTCFlags");
if (state.pc == 0x802745e0) log_function("FUNCTION: SystemCallVector");
if (state.pc == 0x80274664) log_function("FUNCTION: __OSThreadInit");
if (state.pc == 0x802748f8) log_function("FUNCTION: OSGetCurrentThread");
if (state.pc == 0x802748fc) log_function("FUNCTION: GetFont__Q34nw4r3lyt7TextBoxCFv");
if (state.pc == 0x80274904) log_function("FUNCTION: OSDisableScheduler");
if (state.pc == 0x80274940) log_function("FUNCTION: OSEnableScheduler");
if (state.pc == 0x8027497c) log_function("FUNCTION: UnsetRun");
if (state.pc == 0x802749e4) log_function("FUNCTION: __OSGetEffectivePriority");
if (state.pc == 0x80274a20) log_function("FUNCTION: SetEffectivePriority");
if (state.pc == 0x80274bd4) log_function("FUNCTION: __OSPromoteThread");
// if (state.pc == 0x80274c24) log_function("FUNCTION: SelectThread");
if (state.pc == 0x80274e4c) log_function("FUNCTION: __OSReschedule");
if (state.pc == 0x80274e64) log_function("FUNCTION: OSYieldThread");
if (state.pc == 0x80274ea0) log_function("FUNCTION: OSCreateThread");
if (state.pc == 0x8027510c) log_function("FUNCTION: OSExitThread");
if (state.pc == 0x802751f0) log_function("FUNCTION: OSCancelThread");
if (state.pc == 0x802753c8) log_function("FUNCTION: OSResumeThread");
if (state.pc == 0x80275660) log_function("FUNCTION: OSSuspendThread");
if (state.pc == 0x802757f4) log_function("FUNCTION: OSSleepThread");
if (state.pc == 0x802758e0) log_function("FUNCTION: OSWakeupThread");
if (state.pc == 0x802759d4) log_function("FUNCTION: OSGetTime");
if (state.pc == 0x802759ec) log_function("FUNCTION: OSGetTick");
if (state.pc == 0x802759f4) log_function("FUNCTION: __OSGetSystemTime");
if (state.pc == 0x80275a58) log_function("FUNCTION: __OSTimeToSystemTime");
if (state.pc == 0x80275ab0) log_function("FUNCTION: GetDates");
if (state.pc == 0x80275c20) log_function("FUNCTION: OSTicksToCalendarTime");
if (state.pc == 0x80275de8) log_function("FUNCTION: OSUTF8to32");
if (state.pc == 0x80275ef8) log_function("FUNCTION: OSUTF16to32");
if (state.pc == 0x80275fe0) log_function("FUNCTION: OSUTF32toSJIS");
if (state.pc == 0x802761c0) log_function("FUNCTION: __OSInitSTM");
if (state.pc == 0x802763c0) log_function("FUNCTION: __OSSetVIForceDimming");
if (state.pc == 0x802764b8) log_function("FUNCTION: __OSUnRegisterStateEvent");
if (state.pc == 0x80276b54) log_function("FUNCTION: __OSStartPlayRecord");
if (state.pc == 0x80276ba8) log_function("FUNCTION: __OSStopPlayRecord");
if (state.pc == 0x80276d90) log_function("FUNCTION: __OSWriteStateFlags");
if (state.pc == 0x80277040) log_function("FUNCTION: NWC24iPrepareShutdown");
if (state.pc == 0x802771dc) log_function("FUNCTION: NWC24SuspendScheduler");
if (state.pc == 0x802772dc) log_function("FUNCTION: NWC24iRequestShutdown");
if (state.pc == 0x80277348) log_function("FUNCTION: NWC24Shutdown_");
if (state.pc == 0x80277530) log_function("FUNCTION: __OSWriteNandbootInfo");
if (state.pc == 0x80277688) log_function("FUNCTION: __OSReadNandbootInfo");
if (state.pc == 0x80277888) log_function("FUNCTION: exit");
if (state.pc == 0x802778d4) log_function("FUNCTION: PSMTXIdentity");
if (state.pc == 0x80277900) log_function("FUNCTION: PSMTXCopy");
if (state.pc == 0x80277934) log_function("FUNCTION: PSMTXConcat");
if (state.pc == 0x80277a00) log_function("FUNCTION: PSMTXInverse");
if (state.pc == 0x80277af8) log_function("FUNCTION: PSMTXInvXpose");
if (state.pc == 0x80277c3c) log_function("FUNCTION: PSMTXRotTrig");
if (state.pc == 0x80277cec) log_function("FUNCTION: __PSMTXRotAxisRadInternal");
if (state.pc == 0x80277d9c) log_function("FUNCTION: PSMTXRotAxisRad");
if (state.pc == 0x80277e18) log_function("FUNCTION: PSMTXTrans");
if (state.pc == 0x80277e4c) log_function("FUNCTION: PSMTXTransApply");
if (state.pc == 0x80277e98) log_function("FUNCTION: PSMTXScale");
if (state.pc == 0x80277ec0) log_function("FUNCTION: PSMTXScaleApply");
if (state.pc == 0x80277f18) log_function("FUNCTION: PSMTXQuat");
if (state.pc == 0x80277fbc) log_function("FUNCTION: C_MTXLookAt");
if (state.pc == 0x80278130) log_function("FUNCTION: C_MTXLightFrustum");
if (state.pc == 0x802781d4) log_function("FUNCTION: C_MTXLightPerspective");
if (state.pc == 0x80278354) log_function("FUNCTION: PSMTXMultVec");
if (state.pc == 0x802783a8) log_function("FUNCTION: PSMTXMultVecArray");
if (state.pc == 0x80278524) log_function("FUNCTION: C_MTXPerspective");
if (state.pc == 0x80278610) log_function("FUNCTION: C_MTXOrtho");
if (state.pc == 0x802786a8) log_function("FUNCTION: PSMTX44Copy");
if (state.pc == 0x802786ec) log_function("FUNCTION: PSMTX44MultVec");
if (state.pc == 0x80278764) log_function("FUNCTION: PSMTX44MultVecArray");
if (state.pc == 0x80278854) { 
    // dump stack
    for (int i = 0; i < 0x500; i++) {
        u32 addr = state.gprs[1] + i * 4;
        u32 value = mem.read_be_u32(addr);
        log_function("STACK: %08x: %08x", addr, value);
    }
    log_function("FUNCTION: PSVECAdd") ;
}
if (state.pc == 0x80122940) log_function("ASSHOLE3 %08X", state.lr); 
if (state.pc == 0x80278878) log_function("FUNCTION: PSVECSubtract");
if (state.pc == 0x8027889c) log_function("FUNCTION: PSVECScale");
if (state.pc == 0x802788b8) log_function("FUNCTION: PSVECNormalize");
if (state.pc == 0x802788fc) log_function("FUNCTION: PSVECSquareMag");
if (state.pc == 0x80278914) log_function("FUNCTION: PSVECMag");
if (state.pc == 0x80278958) log_function("FUNCTION: PSVECDotProduct");
if (state.pc == 0x80278978) log_function("FUNCTION: PSVECCrossProduct");
if (state.pc == 0x802789b4) log_function("FUNCTION: C_VECHalfAngle");
if (state.pc == 0x80278a8c) log_function("FUNCTION: C_VECReflect");
if (state.pc == 0x80278b60) log_function("FUNCTION: PSVECSquareDistance");
if (state.pc == 0x80278bdc) log_function("FUNCTION: C_QUATMtx");
if (state.pc == 0x80278da8) log_function("FUNCTION: C_QUATSlerp");
if (state.pc == 0x80278f74) log_function("FUNCTION: DVDConvertPathToEntrynum");
if (state.pc == 0x8027927c) log_function("FUNCTION: DVDFastOpen");
if (state.pc == 0x80279308) log_function("FUNCTION: DVDReadAsyncPrio");
if (state.pc == 0x802793f0) log_function("FUNCTION: DVDReadPrio");
if (state.pc == 0x80279830) log_function("FUNCTION: cbForStateReadingFST");
if (state.pc == 0x802799b8) log_function("FUNCTION: cbForStateError");
if (state.pc == 0x80279adc) log_function("FUNCTION: cbForStoreErrorCode2");
if (state.pc == 0x80279b18) log_function("FUNCTION: CategorizeError");
if (state.pc == 0x80279c0c) log_function("FUNCTION: cbForStoreErrorCode3");
if (state.pc == 0x80279cd0) log_function("FUNCTION: cbForStateGettingError");
if (state.pc == 0x8027a1d4) log_function("FUNCTION: cbForUnrecoveredError");
if (state.pc == 0x8027a3b4) log_function("FUNCTION: cbForUnrecoveredErrorRetry");
if (state.pc == 0x8027a9e8) log_function("FUNCTION: cbForStateReadingTOC");
if (state.pc == 0x8027af58) log_function("FUNCTION: cbForStateOpenPartition");
if (state.pc == 0x8027b0e0) log_function("FUNCTION: cbForStateOpenPartition2");
if (state.pc == 0x8027b244) log_function("FUNCTION: cbForStateCheckID1");
if (state.pc == 0x8027b80c) log_function("FUNCTION: cbForStateReset");
if (state.pc == 0x8027b8f0) log_function("FUNCTION: stateDownRotation");
if (state.pc == 0x8027bc20) log_function("FUNCTION: cbForStateCoverClosed");
if (state.pc == 0x8027bcf8) log_function("FUNCTION: cbForPrepareCoverRegister");
if (state.pc == 0x8027cfec) log_function("FUNCTION: DVDInquiryAsync");
// if (state.pc == 0x8027d18c) log_function("FUNCTION: DVDGetDriveStatus");
if (state.pc == 0x8027d238) log_function("FUNCTION: DVDResume");
if (state.pc == 0x8027d6b8) log_function("FUNCTION: __DVDGetCoverStatus");
if (state.pc == 0x8027d780) log_function("FUNCTION: __DVDPrepareResetAsync");
if (state.pc == 0x8027d8a8) log_function("FUNCTION: __DVDPrepareReset");
if (state.pc == 0x8027d9dc) log_function("FUNCTION: __DVDTestAlarm");
if (state.pc == 0x8027da40) log_function("FUNCTION: __DVDPushWaitingQueue");
if (state.pc == 0x8027daa8) log_function("FUNCTION: __DVDPopWaitingQueue");
if (state.pc == 0x8027db48) log_function("FUNCTION: __DVDCheckWaitingQueue");
if (state.pc == 0x8027dba0) log_function("FUNCTION: __DVDGetNextWaitingQueue");
if (state.pc == 0x8027dc00) log_function("FUNCTION: __DVDDequeueWaitingQueue");
if (state.pc == 0x8027dc8c) log_function("FUNCTION: cbForNandWrite");
if (state.pc == 0x8027de30) log_function("FUNCTION: cbForNandCreateDir");
if (state.pc == 0x8027e194) log_function("FUNCTION: doTransactionCallback");
if (state.pc == 0x8027e24c) log_function("FUNCTION: doPrepareCoverRegisterCallback");
if (state.pc == 0x802806b4) log_function("FUNCTION: __VIInit");
// if (state.pc == 0x80280e0c) log_function("FUNCTION: VIWaitForRetrace");
if (state.pc == 0x80281a3c) log_function("FUNCTION: VIConfigurePan");
if (state.pc == 0x80281d90) log_function("FUNCTION: VIFlush");
if (state.pc == 0x80281ea4) log_function("FUNCTION: VISetNextFrameBuffer");
if (state.pc == 0x80281f10) log_function("FUNCTION: VISetBlack");
if (state.pc == 0x80281f90) log_function("FUNCTION: VIGetNextField");
if (state.pc == 0x8028202c) log_function("FUNCTION: VIGetCurrentLine");
if (state.pc == 0x8028211c) log_function("FUNCTION: VIGetScanMode");
if (state.pc == 0x8028217c) log_function("FUNCTION: VIGetDTVStatus");
if (state.pc == 0x802821b8) log_function("FUNCTION: __VIDisplayPositionToXY");
if (state.pc == 0x802823ec) log_function("FUNCTION: VISetVSyncTimingTest");
if (state.pc == 0x802825bc) log_function("FUNCTION: sendSlaveAddr");
if (state.pc == 0x80282f40) log_function("FUNCTION: __VISetYUVSEL");
if (state.pc == 0x80282fe4) log_function("FUNCTION: __VISetFilter4EURGB60");
if (state.pc == 0x8028307c) log_function("FUNCTION: __VISetWSS");
if (state.pc == 0x802830e0) log_function("FUNCTION: __VISetClosedCaption");
if (state.pc == 0x8028314c) log_function("FUNCTION: __VISetMacrovision");
if (state.pc == 0x80283ed4) log_function("FUNCTION: __VISetGammaImm");
if (state.pc == 0x80284068) log_function("FUNCTION: __VISetGamma");
if (state.pc == 0x80284080) log_function("FUNCTION: __VISetTrapFilter");
if (state.pc == 0x802840dc) log_function("FUNCTION: __VISetRGBOverDrive");
if (state.pc == 0x80284170) log_function("FUNCTION: __VISetRGBModeImm");
if (state.pc == 0x802846fc) log_function("FUNCTION: AIInitDMA");
if (state.pc == 0x80284778) log_function("FUNCTION: AIStartDMA");
if (state.pc == 0x8028478c) log_function("FUNCTION: AIGetDMABytesLeft");
if (state.pc == 0x8028479c) log_function("FUNCTION: AIInit");
if (state.pc == 0x8028491c) log_function("FUNCTION: __AIDHandler");
if (state.pc == 0x802849c4) log_function("FUNCTION: __AICallbackStackSwitch");
if (state.pc == 0x80284c54) log_function("FUNCTION: __AXServiceCallbackStack");
if (state.pc == 0x80284db0) log_function("FUNCTION: __AXPushFreeStack");
if (state.pc == 0x80284ddc) log_function("FUNCTION: __AXRemoveFromStack");
if (state.pc == 0x80284e60) log_function("FUNCTION: AXFreeVoice");
if (state.pc == 0x80284edc) log_function("FUNCTION: AXAcquireVoice");
if (state.pc == 0x802853ac) log_function("FUNCTION: __AXGetAuxCInput");
if (state.pc == 0x802853fc) log_function("FUNCTION: __AXProcessAux");
if (state.pc == 0x80285918) log_function("FUNCTION: __AXGetCommandListAddress");
if (state.pc == 0x80285948) log_function("FUNCTION: __AXNextFrame");
if (state.pc == 0x80286308) log_function("FUNCTION: __AXClInit");
if (state.pc == 0x80286364) log_function("FUNCTION: AXSetMasterVolume");
if (state.pc == 0x802866a4) log_function("FUNCTION: __AXDSPResumeCallback");
if (state.pc == 0x8028670c) log_function("FUNCTION: __AXOutInitDSP");
if (state.pc == 0x802867fc) log_function("FUNCTION: __AXOutInit");
if (state.pc == 0x80286a38) log_function("FUNCTION: AXRmtGetSamplesLeft");
if (state.pc == 0x80286a64) log_function("FUNCTION: AXRmtGetSamples");
if (state.pc == 0x80286b28) log_function("FUNCTION: AXRmtAdvancePtr");
if (state.pc == 0x80286b8c) log_function("FUNCTION: __AXDepopFadeMain");
if (state.pc == 0x80286bf8) log_function("FUNCTION: __AXDepopFadeRmt");
if (state.pc == 0x80286c64) log_function("FUNCTION: __AXPrintStudio");
if (state.pc == 0x80286fa8) log_function("FUNCTION: __AXServiceVPB");
if (state.pc == 0x802874f8) log_function("FUNCTION: __AXSyncPBs");
if (state.pc == 0x80287810) log_function("FUNCTION: __AXSetPBDefault");
if (state.pc == 0x80287880) log_function("FUNCTION: __AXVPBInitCommon");
if (state.pc == 0x80287b08) log_function("FUNCTION: AXSetVoiceState");
if (state.pc == 0x80287b78) log_function("FUNCTION: AXSetVoiceAddr");
if (state.pc == 0x80287c70) log_function("FUNCTION: AXGetLpfCoefs");
if (state.pc == 0x8028809c) log_function("FUNCTION: AXFXReverbHiExpSettings");
if (state.pc == 0x8028816c) log_function("FUNCTION: AXFXReverbHiExpShutdown");
if (state.pc == 0x802886d8) log_function("FUNCTION: __AllocDelayLine");
if (state.pc == 0x8028884c) log_function("FUNCTION: __BzeroDelayLines %x", state.lr);
if (state.pc == 0x80288970) log_function("FUNCTION: __FreeDelayLine");
if (state.pc == 0x80288de0) { log_function("FUNCTION: DSPCheckMailToDSP %x", state.lr); 
// dump stack
    for (int i = 0; i < 32; i++) {
        auto reg = state.gprs[1] + i * 4;
        u32 value = mem.read_be_u32(reg);
        log_function("STACK: %08X: %08X", reg, value);

    }
}
if (state.pc == 0x80288df0) log_function("FUNCTION: DSPCheckMailFromDSP");
if (state.pc == 0x80288e00) log_function("FUNCTION: DSPReadMailFromDSP");
if (state.pc == 0x80288e14) log_function("FUNCTION: DSPSendMailToDSP");
if (state.pc == 0x80288e28) { log_function("FUNCTION: DSPInit %x", state.lr);
// dump stack
    for (int i = 0; i < 32; i++) {
        auto reg = state.gprs[1] + i * 4;
        u32 value = mem.read_be_u32(reg);
        log_function("STACK: %08X: %08X", reg, value);

    }
}
if (state.pc == 0x80288ef0) log_function("FUNCTION: DSPAddTask");
if (state.pc == 0x802894a0) log_function("FUNCTION: __DSP_exec_task");
if (state.pc == 0x80289644) log_function("FUNCTION: __DSP_boot_task");
if (state.pc == 0x802897d0) log_function("FUNCTION: __DSP_insert_task");
if (state.pc == 0x802899f4) log_function("FUNCTION: __GXDefaultTlutRegionCallback");
if (state.pc == 0x80289a18) log_function("FUNCTION: __GXShutdown");
if (state.pc == 0x80289b84) log_function("FUNCTION: __GXInitRevisionBits");
if (state.pc == 0x80289cb4) log_function("FUNCTION: GXInit");
if (state.pc == 0x8028ac28) log_function("FUNCTION: GXInitFifoBase");
if (state.pc == 0x8028acb4) log_function("FUNCTION: CPGPLinkCheck");
if (state.pc == 0x8028adac) log_function("FUNCTION: GXSetCPUFifo");
if (state.pc == 0x8028af8c) log_function("FUNCTION: GXSetGPFifo");
if (state.pc == 0x8028b21c) log_function("FUNCTION: __GXSaveFifo");
if (state.pc == 0x8028b40c) log_function("FUNCTION: __GXFifoInit");
if (state.pc == 0x8028b488) log_function("FUNCTION: __GXCleanGPFifo");
if (state.pc == 0x8028b89c) log_function("FUNCTION: GXSetVtxDescv");
if (state.pc == 0x8028baa8) log_function("FUNCTION: __GXSetVCD");
if (state.pc == 0x8028bb58) log_function("FUNCTION: __GXCalculateVLim");
if (state.pc == 0x8028bc84) log_function("FUNCTION: GXGetVtxDesc");
if (state.pc == 0x8028be38) log_function("FUNCTION: GXGetVtxDescv");
if (state.pc == 0x8028bec8) log_function("FUNCTION: GXClearVtxDesc");
if (state.pc == 0x8028befc) log_function("FUNCTION: GXSetVtxAttrFmt");
if (state.pc == 0x8028c09c) log_function("FUNCTION: GXSetVtxAttrFmtv");
if (state.pc == 0x8028c260) log_function("FUNCTION: __GXSetVAT");
if (state.pc == 0x8028c2e0) log_function("FUNCTION: GXGetVtxAttrFmt");
if (state.pc == 0x8028c54c) log_function("FUNCTION: GXGetVtxAttrFmtv");
if (state.pc == 0x8028c5c0) log_function("FUNCTION: GXSetArray");
if (state.pc == 0x8028c600) log_function("FUNCTION: GXInvalidateVtxCache");
if (state.pc == 0x8028c610) log_function("FUNCTION: GXSetTexCoordGen2");
if (state.pc == 0x8028c8e8) log_function("FUNCTION: GXFlush");
if (state.pc == 0x8028c944) log_function("FUNCTION: GXResetWriteGatherPipe");
if (state.pc == 0x8028c978) log_function("FUNCTION: __GXAbort");
if (state.pc == 0x8028cadc) log_function("FUNCTION: GXAbortFrame");
if (state.pc == 0x8028cc90) log_function("FUNCTION: GXSetDrawSync");
if (state.pc == 0x8028cd44) log_function("FUNCTION: GXReadDrawSync");
if (state.pc == 0x8028cd50) log_function("FUNCTION: GXDrawDone");
if (state.pc == 0x8028ce10) log_function("FUNCTION: GXPixModeSync");
if (state.pc == 0x8028ce34) log_function("FUNCTION: GXTexModeSync");
if (state.pc == 0x8028ce58) log_function("FUNCTION: GXPokeAlphaMode");
if (state.pc == 0x8028ce68) log_function("FUNCTION: GXPokeAlphaRead");
if (state.pc == 0x8028ce80) log_function("FUNCTION: GXPokeAlphaUpdate");
if (state.pc == 0x8028ce94) log_function("FUNCTION: GXPokeBlendMode");
if (state.pc == 0x8028cef0) log_function("FUNCTION: GXPokeColorUpdate");
if (state.pc == 0x8028cf04) log_function("FUNCTION: GXPokeDstAlpha");
if (state.pc == 0x8028cf1c) log_function("FUNCTION: GXPokeDither");
if (state.pc == 0x8028cf30) log_function("FUNCTION: GXPokeZMode");
if (state.pc == 0x8028cf90) log_function("FUNCTION: GXTokenInterruptHandler");
// if (state.pc == 0x8028d058) log_function("FUNCTION: GXFinishInterruptHandler");
if (state.pc == 0x8028d0d8) log_function("FUNCTION: __GXPEInit");
if (state.pc == 0x8028d3b4) error_function("FUNCTION: GXBegin");
if (state.pc == 0x8028d500) log_function("FUNCTION: __GXSendFlushPrim");
if (state.pc == 0x8028d5d8) log_function("FUNCTION: GXSetLineWidth");
if (state.pc == 0x8028d60c) log_function("FUNCTION: GXSetPointSize");
if (state.pc == 0x8028d640) log_function("FUNCTION: GXEnableTexOffsets");
if (state.pc == 0x8028d67c) log_function("FUNCTION: GXSetCullMode");
if (state.pc == 0x8028d6a4) log_function("FUNCTION: GXGetCullMode");
if (state.pc == 0x8028d6c0) log_function("FUNCTION: GXSetCoPlanar");
if (state.pc == 0x8028d6f4) log_function("FUNCTION: GXAdjustForOverscan");
if (state.pc == 0x8028d86c) log_function("FUNCTION: GXSetTexCopySrc");
if (state.pc == 0x8028d8ac) log_function("FUNCTION: GXSetDispCopyDst");
if (state.pc == 0x8028d8d0) log_function("FUNCTION: GXSetTexCopyDst");
if (state.pc == 0x8028d9ec) log_function("FUNCTION: GXSetDispCopyFrame2Field");
if (state.pc == 0x8028da0c) log_function("FUNCTION: GXSetCopyClamp");
if (state.pc == 0x8028da34) { biglog = true; log_function("FUNCTION: GXGetYScaleFactor %x", state.cr); }
if (state.pc == 0x8028dc64) log_function("FUNCTION: GXSetDispCopyYScale");
if (state.pc == 0x8028dd30) log_function("FUNCTION: GXSetCopyClear");
if (state.pc == 0x8028dda8) log_function("FUNCTION: GXSetCopyFilter");
if (state.pc == 0x8028df8c) log_function("FUNCTION: GXSetDispCopyGamma");
if (state.pc == 0x8028dfa0) log_function("FUNCTION: GXCopyDisp %x", state.cr);
if (state.pc == 0x8028e0dc) log_function("FUNCTION: GXCopyTex");
if (state.pc == 0x8028e234) log_function("FUNCTION: GXClearBoundingBox");
if (state.pc == 0x8028e2a0) log_function("FUNCTION: GXInitLightAttn");
if (state.pc == 0x8028e444) log_function("FUNCTION: GXInitLightDistAttn");
if (state.pc == 0x8028e524) log_function("FUNCTION: GXInitLightDir");
if (state.pc == 0x8028e540) log_function("FUNCTION: GXInitLightColor");
if (state.pc == 0x8028e54c) log_function("FUNCTION: GXLoadLightObjImm");
if (state.pc == 0x8028e5c8) log_function("FUNCTION: GXSetChanAmbColor");
if (state.pc == 0x8028e6a0) log_function("FUNCTION: GXSetChanMatColor");
if (state.pc == 0x8028e778) log_function("FUNCTION: GXSetNumChans");
if (state.pc == 0x8028e964) log_function("FUNCTION: __GetImageTileCount");
if (state.pc == 0x8028ea24) log_function("FUNCTION: GXInitTexObj");
if (state.pc == 0x8028ec30) log_function("FUNCTION: GXInitTexObjCI");
if (state.pc == 0x8028ec78) log_function("FUNCTION: GXInitTexObjLOD");
if (state.pc == 0x8028ed7c) log_function("FUNCTION: GXInitTexObjData");
if (state.pc == 0x8028ed8c) log_function("FUNCTION: GXInitTexObjWrapMode");
if (state.pc == 0x8028eda8) log_function("FUNCTION: GXInitTexObjFilter");
if (state.pc == 0x8028edd0) log_function("FUNCTION: GXGetTexObjWidth");
if (state.pc == 0x8028ede4) log_function("FUNCTION: GXGetTexObjHeight");
if (state.pc == 0x8028ee00) log_function("FUNCTION: GXGetTexObjMipMap");
if (state.pc == 0x8028ee14) log_function("FUNCTION: GXLoadTexObjPreLoaded");
if (state.pc == 0x8028ef78) log_function("FUNCTION: GXLoadTexObj");
if (state.pc == 0x8028efcc) log_function("FUNCTION: GXInitTlutObj");
if (state.pc == 0x8028eff4) log_function("FUNCTION: GXLoadTlut");
if (state.pc == 0x8028f088) log_function("FUNCTION: GXInitTexCacheRegion");
if (state.pc == 0x8028f13c) log_function("FUNCTION: GXInitTexPreLoadRegion");
if (state.pc == 0x8028f178) log_function("FUNCTION: GXInitTlutRegion");
if (state.pc == 0x8028f198) log_function("FUNCTION: GXInvalidateTexAll");
if (state.pc == 0x8028f1e0) log_function("FUNCTION: GXSetTexRegionCallback");
if (state.pc == 0x8028f1f4) log_function("FUNCTION: GXSetTlutRegionCallback");
if (state.pc == 0x8028f208) log_function("FUNCTION: GXPreLoadEntireTexture");
if (state.pc == 0x8028f46c) log_function("FUNCTION: __SetSURegs");
if (state.pc == 0x8028f4fc) log_function("FUNCTION: __GXSetSUTexRegs");
if (state.pc == 0x8028f664) log_function("FUNCTION: __GXSetTmemConfig");
if (state.pc == 0x8028fa20) log_function("FUNCTION: GXSetIndTexMtx");
if (state.pc == 0x8028fb74) log_function("FUNCTION: GXSetIndTexCoordScale");
if (state.pc == 0x8028fc78) log_function("FUNCTION: GXSetIndTexOrder");
if (state.pc == 0x8028fd44) log_function("FUNCTION: GXSetNumIndStages");
if (state.pc == 0x8028fe04) log_function("FUNCTION: __GXSetIndirectMask");
if (state.pc == 0x8028fd64) log_function("FUNCTION: GXSetTevDirect");
if (state.pc == 0x8028fdac) log_function("FUNCTION: GXSetTevIndWarp");
if (state.pc == 0x8028feec) log_function("FUNCTION: GXSetTevColorIn");
if (state.pc == 0x8028ff2c) log_function("FUNCTION: GXSetTevAlphaIn");
if (state.pc == 0x8028ff6c) log_function("FUNCTION: GXSetTevColorOp");
if (state.pc == 0x8028ffc4) log_function("FUNCTION: GXSetTevAlphaOp");
if (state.pc == 0x8029001c) log_function("FUNCTION: GXSetTevColor");
if (state.pc == 0x8029007c) log_function("FUNCTION: GXSetTevColorS10");
if (state.pc == 0x802900e0) log_function("FUNCTION: GXSetTevKColor");
if (state.pc == 0x8029013c) log_function("FUNCTION: GXSetTevKColorSel");
if (state.pc == 0x8029018c) log_function("FUNCTION: GXSetTevKAlphaSel");
if (state.pc == 0x802901dc) log_function("FUNCTION: GXSetTevSwapMode");
if (state.pc == 0x80290218) log_function("FUNCTION: GXSetTevSwapModeTable");
if (state.pc == 0x80290358) log_function("FUNCTION: GXSetTevOrder");
if (state.pc == 0x80290294) log_function("FUNCTION: GXSetAlphaCompare");
if (state.pc == 0x802902cc) log_function("FUNCTION: GXSetZTexture");
if (state.pc == 0x80290704) log_function("FUNCTION: GXSetFogRangeAdj");
if (state.pc == 0x80290828) log_function("FUNCTION: GXSetBlendMode");
if (state.pc == 0x80290878) log_function("FUNCTION: GXSetColorUpdate");
if (state.pc == 0x802908a4) log_function("FUNCTION: GXSetAlphaUpdate");
if (state.pc == 0x802908d0) log_function("FUNCTION: GXSetZMode");
if (state.pc == 0x80290904) log_function("FUNCTION: GXSetZCompLoc");
if (state.pc == 0x80290934) log_function("FUNCTION: GXSetPixelFmt");
if (state.pc == 0x802909dc) log_function("FUNCTION: GXSetDither");
if (state.pc == 0x80290a08) log_function("FUNCTION: GXSetDstAlpha");
if (state.pc == 0x80290a38) log_function("FUNCTION: GXSetFieldMask");
if (state.pc == 0x80290adc) log_function("FUNCTION: GXDrawSphere");
if (state.pc == 0x80290eac) log_function("FUNCTION: GXDrawCubeFace");
if (state.pc == 0x802910ac) log_function("FUNCTION: GXDrawCube");
if (state.pc == 0x80291654) log_function("FUNCTION: __GXSetProjection");
if (state.pc == 0x80291698) log_function("FUNCTION: GXSetProjection");
if (state.pc == 0x802916fc) log_function("FUNCTION: GXSetProjectionv");
if (state.pc == 0x80291748) log_function("FUNCTION: GXGetProjectionv");
if (state.pc == 0x80291788) log_function("FUNCTION: GXLoadPosMtxImm");
if (state.pc == 0x802917d8) log_function("FUNCTION: GXLoadNrmMtxImm");
if (state.pc == 0x80291830) log_function("FUNCTION: GXSetCurrentMtx");
if (state.pc == 0x80291850) log_function("FUNCTION: GXLoadTexMtxImm");
if (state.pc == 0x80291904) log_function("FUNCTION: __GXSetViewport");
if (state.pc == 0x80291994) log_function("FUNCTION: GXSetViewportJitter");
if (state.pc == 0x802919fc) log_function("FUNCTION: GXGetViewportv");
if (state.pc == 0x80291a1c) log_function("FUNCTION: GXSetZScaleOffset");
if (state.pc == 0x80291a4c) log_function("FUNCTION: GXSetScissor");
if (state.pc == 0x80291ab4) log_function("FUNCTION: GXGetScissor");
if (state.pc == 0x80291afc) log_function("FUNCTION: GXSetScissorBoxOffset");
if (state.pc == 0x80291b38) log_function("FUNCTION: GXSetClipMode");
if (state.pc == 0x80292414) log_function("FUNCTION: GXClearGPMetric");
if (state.pc == 0x80292564) log_function("FUNCTION: MEMiInitHeapHead");
if (state.pc == 0x80292890) log_function("FUNCTION: MEMFindContainHeap");
if (state.pc == 0x80292bd4) log_function("FUNCTION: AllocFromHead_");
if (state.pc == 0x80292cb0) log_function("FUNCTION: AllocFromTail_");
if (state.pc == 0x80292d78) log_function("FUNCTION: RecycleRegion_");
if (state.pc == 0x80292ee0) log_function("FUNCTION: MEMCreateExpHeapEx");
if (state.pc == 0x80292fc0) log_function("FUNCTION: MEMAllocFromExpHeapEx");
if (state.pc == 0x80293070) log_function("FUNCTION: MEMFreeToExpHeap");
if (state.pc == 0x8029313c) log_function("FUNCTION: MEMGetAllocatableSizeForExpHeapEx");
if (state.pc == 0x80293214) log_function("FUNCTION: MEMGetSizeForMBlockExpHeap");
if (state.pc == 0x802932d0) log_function("FUNCTION: MEMAllocFromFrmHeapEx");
if (state.pc == 0x802933f0) log_function("FUNCTION: MEMFreeToFrmHeap");
if (state.pc == 0x80293490) log_function("FUNCTION: MEMGetAllocatableSizeForFrmHeapEx");
if (state.pc == 0x802936f8) log_function("FUNCTION: MEMFreeToUnitHeap");
if (state.pc == 0x80293794) log_function("FUNCTION: MEMAllocFromAllocator");
if (state.pc == 0x802937a4) log_function("FUNCTION: MEMFreeToAllocator");
if (state.pc == 0x802939fc) log_function("FUNCTION: InitializeUART");
if (state.pc == 0x80293f00) log_function("FUNCTION: ISFS_CreateDir");
if (state.pc == 0x80293ff4) log_function("FUNCTION: ISFS_CreateDirAsync");
if (state.pc == 0x802940e8) log_function("FUNCTION: ISFS_ReadDir");
if (state.pc == 0x8029423c) log_function("FUNCTION: ISFS_ReadDirAsync");
if (state.pc == 0x80294384) log_function("FUNCTION: ISFS_GetAttr");
if (state.pc == 0x802944dc) log_function("FUNCTION: ISFS_GetAttrAsync");
if (state.pc == 0x802946e8) log_function("FUNCTION: ISFS_DeleteAsync");
if (state.pc == 0x802947b8) log_function("FUNCTION: ISFS_RenameAsync");
if (state.pc == 0x802948bc) log_function("FUNCTION: ISFS_GetUsageAsync");
if (state.pc == 0x802949e0) log_function("FUNCTION: ISFS_CreateFile");
if (state.pc == 0x80294ad4) log_function("FUNCTION: ISFS_CreateFileAsync");
if (state.pc == 0x80294bc8) log_function("FUNCTION: ISFS_Open");
if (state.pc == 0x80294c90) log_function("FUNCTION: ISFS_OpenAsync");
if (state.pc == 0x80294d48) log_function("FUNCTION: ISFS_SeekAsync");
if (state.pc == 0x802950c0) log_function("FUNCTION: IPCReadReg");
if (state.pc == 0x802950d0) log_function("FUNCTION: IPCWriteReg");
if (state.pc == 0x802950f8) log_function("FUNCTION: strnlen");
if (state.pc == 0x80295834) log_function("FUNCTION: IOS_OpenAsync");
if (state.pc == 0x8029594c) { bazinga++; log_function("FUNCTION: IOS_Open");}
if (state.pc == 0x80295a6c) log_function("FUNCTION: IOS_CloseAsync");
if (state.pc == 0x80295b2c) log_function("FUNCTION: IOS_Close");
if (state.pc == 0x80295bd4) log_function("FUNCTION: IOS_ReadAsync");
if (state.pc == 0x80295cd4) log_function("FUNCTION: IOS_Read");
if (state.pc == 0x80295ddc) log_function("FUNCTION: IOS_WriteAsync");
if (state.pc == 0x80295edc) log_function("FUNCTION: IOS_Write");
if (state.pc == 0x802960c4) {
    log_function("FUNCTION: IOS_IoctlAsync");
    // dump stack
    for (int i = 0; i < 0x30; i++) {
        u32 addr = state.gprs[1] + i * 4;
        u32 value = mem.read_be_u32(addr);
        log_function("STACK: %08x: %08x\n", addr, value);
    }
}
if (state.pc == 0x802961fc) log_function("FUNCTION: IOS_Ioctl");
if (state.pc == 0x8029632c) log_function("FUNCTION: __ios_Ioctlv");
if (state.pc == 0x80296468) {log_function("FUNCTION: IOS_IoctlvAsync %x", state.lr); 
    log_function("FUNCTION: IOS_IoctlAsync");
    // dump stack
    for (int i = 0; i < 0x30; i++) {
        u32 addr = state.gprs[1] + i * 4;
        u32 value = mem.read_be_u32(addr);
        log_function("STACK: %08x: %08x", addr, value);
    }}
if (state.pc == 0x8029654c) log_function("FUNCTION: IOS_Ioctlv");
if (state.pc == 0x80296840) log_function("FUNCTION: __iosAlloc");
if (state.pc == 0x80296c34) log_function("FUNCTION: IPCiProfInit");
if (state.pc == 0x80297010) log_function("FUNCTION: NANDDelete");
if (state.pc == 0x802970c0) log_function("FUNCTION: NANDDeleteAsync");
if (state.pc == 0x80297198) log_function("FUNCTION: NANDPrivateDeleteAsync");
if (state.pc == 0x80297418) log_function("FUNCTION: NANDSeekAsync");
if (state.pc == 0x802974c8) log_function("FUNCTION: nandCreateDir");
if (state.pc == 0x8029766c) log_function("FUNCTION: nandComposePerm");
if (state.pc == 0x802976c0) log_function("FUNCTION: nandSplitPerm");
if (state.pc == 0x8029774c) log_function("FUNCTION: nandGetStatus");
if (state.pc == 0x802978a0) log_function("FUNCTION: nandGetStatusCallback");
if (state.pc == 0x80297914) log_function("FUNCTION: NANDPrivateGetStatusAsync");
if (state.pc == 0x80297aac) log_function("FUNCTION: NANDOpen");
if (state.pc == 0x80297b38) log_function("FUNCTION: NANDPrivateOpen");
if (state.pc == 0x80297bc4) log_function("FUNCTION: NANDOpenAsync");
if (state.pc == 0x80297c3c) log_function("FUNCTION: NANDPrivateOpenAsync");
if (state.pc == 0x80297cb4) log_function("FUNCTION: nandOpenCallback");
if (state.pc == 0x80297d2c) log_function("FUNCTION: NANDClose");
if (state.pc == 0x80297d98) log_function("FUNCTION: NANDCloseAsync");
if (state.pc == 0x802985d4) log_function("FUNCTION: nandReadCloseCallback");
if (state.pc == 0x80298630) log_function("FUNCTION: nandCloseCallback");
if (state.pc == 0x80298760) log_function("FUNCTION: nandGetHeadToken");
if (state.pc == 0x80298834) log_function("FUNCTION: nandGetRelativeName");
if (state.pc == 0x802988cc) log_function("FUNCTION: nandConvertPath");
if (state.pc == 0x80298a08) log_function("FUNCTION: nandIsPrivatePath");
if (state.pc == 0x80298a3c) log_function("FUNCTION: nandIsUnderPrivatePath");
if (state.pc == 0x80298b7c) log_function("FUNCTION: nandGenerateAbsPath");
if (state.pc == 0x80298c44) log_function("FUNCTION: nandGetParentDirectory");
if (state.pc == 0x80298f5c) log_function("FUNCTION: nandOnShutdown");
if (state.pc == 0x80299028) log_function("FUNCTION: nandShutdownCallback");
if (state.pc == 0x80299034) log_function("FUNCTION: nandChangeDir");
if (state.pc == 0x802994dc) log_function("FUNCTION: NANDGetHomeDir");
if (state.pc == 0x8029961c) log_function("FUNCTION: nandGetType");
if (state.pc == 0x80299c94) log_function("FUNCTION: NANDCheckAsync");
if (state.pc == 0x80299d40) log_function("FUNCTION: nandUserAreaCallback");
if (state.pc == 0x8029a814) log_function("FUNCTION: UnpackItem");
if (state.pc == 0x8029a9ac) log_function("FUNCTION: DeleteItemByID");
if (state.pc == 0x8029ab3c) log_function("FUNCTION: CreateItemByID");
if (state.pc == 0x8029adb4) log_function("FUNCTION: SCFindByteArrayItem");
if (state.pc == 0x8029ae94) log_function("FUNCTION: SCReplaceByteArrayItem");
if (state.pc == 0x8029afb8) log_function("FUNCTION: SCReplaceIntegerItem");
if (state.pc == 0x8029b92c) log_function("FUNCTION: SCGetDisplayOffsetH");
if (state.pc == 0x8029b9ac) log_function("FUNCTION: SCGetLanguage");
if (state.pc == 0x8029ba18) log_function("FUNCTION: SCGetProgressiveMode");
if (state.pc == 0x8029ba6c) log_function("FUNCTION: SCGetScreenSaverMode");
if (state.pc == 0x8029bac0) log_function("FUNCTION: SCGetSoundMode");
if (state.pc == 0x8029bb24) log_function("FUNCTION: SCGetCounterBias");
if (state.pc == 0x8029bcf0) log_function("FUNCTION: __SCF1");
if (state.pc == 0x8029be5c) log_function("FUNCTION: SCGetProductArea");
if (state.pc == 0x8029c100) log_function("FUNCTION: gki_buffer_init");
if (state.pc == 0x8029c3ac) log_function("FUNCTION: GKI_init_q");
if (state.pc == 0x8029c3c0) log_function("FUNCTION: GKI_getbuf");
if (state.pc == 0x8029c560) log_function("FUNCTION: GKI_getpoolbuf %x", state.lr);
if (state.pc == 0x8029c648) log_function("FUNCTION: GKI_freebuf");
if (state.pc == 0x8029c7b8) log_function("FUNCTION: GKI_get_buf_size");
if (state.pc == 0x8029c7fc) log_function("FUNCTION: GKI_send_msg");
if (state.pc == 0x8029c9b8) log_function("FUNCTION: GKI_read_mbox");
if (state.pc == 0x8029ca68) log_function("FUNCTION: GKI_enqueue");
if (state.pc == 0x8029cba4) log_function("FUNCTION: GKI_enqueue_head");
if (state.pc == 0x8029cce4) log_function("FUNCTION: GKI_dequeue");
if (state.pc == 0x8029cd84) log_function("FUNCTION: GKI_remove_from_queue");
if (state.pc == 0x8029ce50) log_function("FUNCTION: GKI_getnext");
if (state.pc == 0x8029ce6c) log_function("FUNCTION: GKI_queue_is_empty");
if (state.pc == 0x8029ce7c) log_function("FUNCTION: GKI_create_pool");
if (state.pc == 0x8029d3e0) log_function("FUNCTION: GKI_get_tick_count");
if (state.pc == 0x8029d3f4) log_function("FUNCTION: GKI_start_timer");
if (state.pc == 0x8029d544) log_function("FUNCTION: GKI_stop_timer");
if (state.pc == 0x8029d5e0) log_function("FUNCTION: GKI_update_timer_list");
if (state.pc == 0x8029d66c) log_function("FUNCTION: GKI_add_to_timer_list");
if (state.pc == 0x8029d758) log_function("FUNCTION: GKI_remove_from_timer_list");
if (state.pc == 0x8029d90c) log_function("FUNCTION: GKI_shutdown");
if (state.pc == 0x8029d9c4) log_function("FUNCTION: GKI_send_event");
if (state.pc == 0x8029da70) log_function("FUNCTION: GKI_enable %x", state.lr);
if (state.pc == 0x8029da94) log_function("FUNCTION: GKI_disable");
if (state.pc == 0x8029dadc) log_function("FUNCTION: GKI_os_malloc");
if (state.pc == 0x8029db30) log_function("FUNCTION: hcisu_h2_receive_msg");
if (state.pc == 0x8029dec8) log_function("FUNCTION: hcisu_h2_send_msg_now");
if (state.pc == 0x8029e074) log_function("FUNCTION: hcisu_h2_init");
if (state.pc == 0x8029e0a0) log_function("FUNCTION: hcisu_h2_open");
if (state.pc == 0x8029e108) log_function("FUNCTION: hcisu_h2_close");
if (state.pc == 0x8029e13c) log_function("FUNCTION: hcisu_h2_send");
if (state.pc == 0x8029e1a8) log_function("FUNCTION: uusb_CloseDeviceCB");
if (state.pc == 0x8029f594) log_function("FUNCTION: UUSB_Close");
if (state.pc == 0x8029f6a4) log_function("FUNCTION: bte_hcisu_task");
if (state.pc == 0x8029f708) log_function("FUNCTION: bte_hcisu_close");
if (state.pc == 0x8029f8e4) log_function("FUNCTION: BTA_Init");
if (state.pc == 0x8029f9c0) log_function("FUNCTION: BTA_CleanUp");
if (state.pc == 0x8029fa64) log_function("FUNCTION: btu_task_msg_handler");
if (state.pc == 0x8029fdf0) log_function("FUNCTION: btu_start_timer");
if (state.pc == 0x8029fe60) log_function("FUNCTION: btu_stop_timer");
if (state.pc == 0x8029fe74) log_function("FUNCTION: bdcpy");
if (state.pc == 0x8029fea8) log_function("FUNCTION: bdcmp");
if (state.pc == 0x8029ff58) log_function("FUNCTION: bta_sys_compress_register");
if (state.pc == 0x8029ff68) log_function("FUNCTION: bta_sys_pm_register");
if (state.pc == 0x8029ff78) log_function("FUNCTION: bta_sys_conn_open");
if (state.pc == 0x802a003c) log_function("FUNCTION: bta_sys_conn_close");
if (state.pc == 0x802a0100) log_function("FUNCTION: bta_sys_sco_close");
if (state.pc == 0x802a0134) log_function("FUNCTION: bta_sys_idle");
if (state.pc == 0x802a0200) log_function("FUNCTION: bta_sys_event");
if (state.pc == 0x802a02ec) log_function("FUNCTION: bta_sys_timer_update");
if (state.pc == 0x802a0320) log_function("FUNCTION: bta_sys_sendmsg");
if (state.pc == 0x802a033c) log_function("FUNCTION: bta_sys_start_timer");
if (state.pc == 0x802a0370) log_function("FUNCTION: bta_sys_disable");
if (state.pc == 0x802a038c) log_function("FUNCTION: GetLifeStatus__Q34nw4r2ef16ReferencedObjectCFv");
if (state.pc == 0x802a042c) log_function("FUNCTION: ptim_timer_update");
if (state.pc == 0x802a04e0) log_function("FUNCTION: ptim_start_timer");
if (state.pc == 0x802a05c0) log_function("FUNCTION: DestroyHeap__Q44nw4r3snd6detail8AxfxImplFv");
if (state.pc == 0x802a0714) log_function("FUNCTION: bta_dm_disable");
if (state.pc == 0x802a07c4) log_function("FUNCTION: bta_dm_disable_timer_cback");
if (state.pc == 0x802a0888) log_function("FUNCTION: bta_dm_set_visibility");
if (state.pc == 0x802a08d0) log_function("FUNCTION: bta_dm_bond");
if (state.pc == 0x802a0940) log_function("FUNCTION: bta_dm_pin_reply");
if (state.pc == 0x802a09dc) log_function("FUNCTION: bta_dm_auth_reply");
if (state.pc == 0x802a0ab0) log_function("FUNCTION: bta_dm_search_start");
if (state.pc == 0x802a0b10) log_function("FUNCTION: bta_dm_search_cancel");
if (state.pc == 0x802a0ca8) log_function("FUNCTION: bta_dm_inq_cmpl");
if (state.pc == 0x802a0ecc) log_function("FUNCTION: bta_dm_rmt_name");
if (state.pc == 0x802a1038) log_function("FUNCTION: bta_dm_disc_rmt_name");
if (state.pc == 0x802a109c) log_function("FUNCTION: bta_dm_sdp_result");
if (state.pc == 0x802a1304) log_function("FUNCTION: bta_dm_search_cmpl");
if (state.pc == 0x802a131c) log_function("FUNCTION: bta_dm_disc_result");
if (state.pc == 0x802a136c) log_function("FUNCTION: bta_dm_search_result");
if (state.pc == 0x802a13f4) log_function("FUNCTION: bta_dm_search_timer_cback");
if (state.pc == 0x802a1440) log_function("FUNCTION: bta_dm_free_sdp_db");
if (state.pc == 0x802a1484) log_function("FUNCTION: bta_dm_queue_search");
if (state.pc == 0x802a14cc) log_function("FUNCTION: bta_dm_queue_disc");
if (state.pc == 0x802a159c) log_function("FUNCTION: bta_dm_search_cancel_transac_cmpl");
if (state.pc == 0x802a15f8) log_function("FUNCTION: bta_dm_search_cancel_notify");
if (state.pc == 0x802a1610) log_function("FUNCTION: bta_dm_find_services");
if (state.pc == 0x802a17b0) log_function("FUNCTION: bta_dm_discover_next_device");
if (state.pc == 0x802a1890) log_function("FUNCTION: bta_dm_sdp_callback");
if (state.pc == 0x802a18d8) log_function("FUNCTION: bta_dm_inq_results_cb");
if (state.pc == 0x802a1968) log_function("FUNCTION: bta_dm_inq_cmpl_cb");
if (state.pc == 0x802a19b4) log_function("FUNCTION: bta_dm_service_search_remname_cback");
if (state.pc == 0x802a19f4) log_function("FUNCTION: bta_dm_remname_cback");
if (state.pc == 0x802a1a80) log_function("FUNCTION: bta_dm_disc_remname_cback");
if (state.pc == 0x802a1b0c) log_function("FUNCTION: bta_dm_authorize_cback");
if (state.pc == 0x802a1bd4) log_function("FUNCTION: bta_dm_pinname_cback");
if (state.pc == 0x802a1c94) log_function("FUNCTION: bta_dm_pin_cback");
if (state.pc == 0x802a1dc4) log_function("FUNCTION: bta_dm_link_key_request_cback");
if (state.pc == 0x802a1dcc) log_function("FUNCTION: bta_dm_new_link_key_cback");
if (state.pc == 0x802a1e68) log_function("FUNCTION: bta_dm_authentication_complete_cback");
if (state.pc == 0x802a1eec) log_function("FUNCTION: bta_dm_local_addr_cback");
if (state.pc == 0x802a1f14) log_function("FUNCTION: bta_dm_signal_strength");
if (state.pc == 0x802a1f50) log_function("FUNCTION: bta_dm_signal_strength_timer_cback");
if (state.pc == 0x802a2044) log_function("FUNCTION: bta_dm_acl_change_cback");
if (state.pc == 0x802a20b4) log_function("FUNCTION: bta_dm_acl_change");
if (state.pc == 0x802a2350) log_function("FUNCTION: bta_dm_rssi_cback");
if (state.pc == 0x802a23bc) log_function("FUNCTION: bta_dm_link_quality_cback");
if (state.pc == 0x802a2428) log_function("FUNCTION: bta_dm_l2cap_server_compress_cback");
if (state.pc == 0x802a250c) log_function("FUNCTION: bta_dm_compress_cback");
if (state.pc == 0x802a2744) log_function("FUNCTION: bta_dm_rm_cback");
if (state.pc == 0x802a284c) log_function("FUNCTION: bta_dm_keep_acl");
if (state.pc == 0x802a29c8) log_function("FUNCTION: BTA_DisableBluetooth");
if (state.pc == 0x802a2a38) log_function("FUNCTION: BTA_DmSetDeviceName");
if (state.pc == 0x802a2a9c) log_function("FUNCTION: BTA_DmSetVisibility");
if (state.pc == 0x802a2af4) log_function("FUNCTION: BTA_DmSearch");
if (state.pc == 0x802a2b78) log_function("FUNCTION: BTA_DmSearchCancel");
if (state.pc == 0x802a2bb0) log_function("FUNCTION: BTA_DmPinReply");
if (state.pc == 0x802a2d2c) log_function("FUNCTION: BTA_DmRemoveDevice");
if (state.pc == 0x802a2f74) log_function("FUNCTION: bta_dm_disable_pm");
if (state.pc == 0x802a2f8c) log_function("FUNCTION: bta_dm_pm_cback");
if (state.pc == 0x802a330c) log_function("FUNCTION: bta_dm_pm_set_mode");
if (state.pc == 0x802a368c) log_function("FUNCTION: bta_dm_pm_btm_cback");
if (state.pc == 0x802a3704) log_function("FUNCTION: bta_dm_pm_timer_cback");
if (state.pc == 0x802a37fc) log_function("FUNCTION: bta_dm_pm_btm_status");
if (state.pc == 0x802a3a9c) log_function("FUNCTION: bta_hh_api_disable");
if (state.pc == 0x802a3ba0) log_function("FUNCTION: bta_hh_disc_cmpl");
if (state.pc == 0x802a3c44) log_function("FUNCTION: bta_hh_sdp_cback");
if (state.pc == 0x802a3d78) log_function("FUNCTION: bta_hh_start_sdp");
if (state.pc == 0x802a3f0c) log_function("FUNCTION: bta_hh_sdp_cmpl");
if (state.pc == 0x802a4074) log_function("FUNCTION: bta_hh_api_disc_act");
if (state.pc == 0x802a40dc) log_function("FUNCTION: bta_hh_open_cmpl_act");
if (state.pc == 0x802a4204) log_function("FUNCTION: bta_hh_open_act");
if (state.pc == 0x802a42bc) log_function("FUNCTION: bta_hh_data_act");
if (state.pc == 0x802a4314) log_function("FUNCTION: bta_hh_handsk_act");
if (state.pc == 0x802a457c) log_function("FUNCTION: bta_hh_ctrl_dat_act");
if (state.pc == 0x802a4774) log_function("FUNCTION: bta_hh_close_act");
if (state.pc == 0x802a4974) log_function("FUNCTION: bta_hh_get_dscp_act");
if (state.pc == 0x802a4990) log_function("FUNCTION: bta_hh_maint_dev_act");
if (state.pc == 0x802a4af4) log_function("FUNCTION: bta_hh_get_acl_q_info");
if (state.pc == 0x802a4c10) log_function("FUNCTION: bta_hh_write_dev_act");
if (state.pc == 0x802a50f8) log_function("FUNCTION: BTA_HhDisable");
if (state.pc == 0x802a5130) log_function("FUNCTION: BTA_HhClose");
if (state.pc == 0x802a5194) log_function("FUNCTION: BTA_HhOpen");
if (state.pc == 0x802a5248) log_function("FUNCTION: BTA_HhSendData");
if (state.pc == 0x802a52d8) log_function("FUNCTION: BTA_HhAddDev");
if (state.pc == 0x802a5380) log_function("FUNCTION: BTA_HhRemoveDev");
if (state.pc == 0x802a53ec) log_function("FUNCTION: BTA_HhGetAclQueueInfo");
if (state.pc == 0x802a5794) log_function("FUNCTION: bta_hh_hdl_event");
if (state.pc == 0x802a5ad0) log_function("FUNCTION: bta_hh_clean_up_kdev");
if (state.pc == 0x802a5b50) log_function("FUNCTION: bta_hh_add_device_to_list");
if (state.pc == 0x802a5c0c) log_function("FUNCTION: bta_hh_tod_spt");
if (state.pc == 0x802a5d5c) log_function("FUNCTION: btm_handle_to_acl_index");
if (state.pc == 0x802a5de0) log_function("FUNCTION: btm_acl_created");
if (state.pc == 0x802a60f4) log_function("FUNCTION: btm_acl_removed");
if (state.pc == 0x802a61b8) log_function("FUNCTION: btm_acl_device_down");
if (state.pc == 0x802a621c) log_function("FUNCTION: BTM_SwitchRole");
if (state.pc == 0x802a6438) log_function("FUNCTION: btm_acl_encrypt_change");
if (state.pc == 0x802a65a8) log_function("FUNCTION: BTM_SetLinkPolicy");
if (state.pc == 0x802a6798) log_function("FUNCTION: BTM_SetDefaultLinkPolicy");
if (state.pc == 0x802a67a8) log_function("FUNCTION: btm_read_link_policy_complete");
if (state.pc == 0x802a68ac) log_function("FUNCTION: btm_read_remote_version_complete");
if (state.pc == 0x802a6938) log_function("FUNCTION: btm_read_remote_features_complete");
if (state.pc == 0x802a6b64) log_function("FUNCTION: BTM_SetDefaultLinkSuperTout");
if (state.pc == 0x802a6b74) log_function("FUNCTION: BTM_IsAclConnectionUp");
if (state.pc == 0x802a6c4c) log_function("FUNCTION: BTM_GetNumAclLinks");
if (state.pc == 0x802a6ca8) log_function("FUNCTION: btm_get_acl_disc_reason_code");
if (state.pc == 0x802a6cb8) log_function("FUNCTION: BTM_GetHCIConnHandle");
if (state.pc == 0x802a6d54) log_function("FUNCTION: btm_process_clk_off_comp_evt");
if (state.pc == 0x802a6df0) log_function("FUNCTION: btm_acl_role_changed");
if (state.pc == 0x802a6fe4) log_function("FUNCTION: btm_acl_timeout");
if (state.pc == 0x802a7040) log_function("FUNCTION: btm_get_max_packet_size");
if (state.pc == 0x802a71e0) log_function("FUNCTION: BTM_AclRegisterForChanges");
if (state.pc == 0x802a7224) log_function("FUNCTION: btm_qos_setup_complete");
if (state.pc == 0x802a72fc) log_function("FUNCTION: BTM_ReadRSSI");
if (state.pc == 0x802a7438) log_function("FUNCTION: BTM_ReadLinkQuality");
if (state.pc == 0x802a7574) log_function("FUNCTION: btm_read_rssi_complete");
if (state.pc == 0x802a7690) log_function("FUNCTION: btm_read_link_quality_complete");
if (state.pc == 0x802a77a8) log_function("FUNCTION: btm_remove_acl");
if (state.pc == 0x802a7864) log_function("FUNCTION: btm_chg_all_acl_pkt_types");
if (state.pc == 0x802a7c0c) log_function("FUNCTION: BTM_SecDeleteDevice");
if (state.pc == 0x802a7cb8) log_function("FUNCTION: BTM_SecReadDevName");
if (state.pc == 0x802a7d58) log_function("FUNCTION: btm_sec_alloc_dev");
if (state.pc == 0x802a7e78) log_function("FUNCTION: btm_find_dev_by_handle");
if (state.pc == 0x802a7f30) log_function("FUNCTION: btm_find_dev");
if (state.pc == 0x802a81f0) log_function("FUNCTION: btm_db_reset");
if (state.pc == 0x802a82a0) log_function("FUNCTION: BTM_DeviceReset");
if (state.pc == 0x802a833c) log_function("FUNCTION: BTM_SendHciReset");
if (state.pc == 0x802a83e4) log_function("FUNCTION: BTM_IsDeviceUp");
if (state.pc == 0x802a8400) log_function("FUNCTION: BTM_SetAfhChannels");
if (state.pc == 0x802a84f0) log_function("FUNCTION: btm_dev_timeout");
if (state.pc == 0x802a8788) log_function("FUNCTION: btm_reset_complete");
if (state.pc == 0x802a894c) log_function("FUNCTION: btm_read_hci_buf_size_complete");
if (state.pc == 0x802a8a14) log_function("FUNCTION: btm_read_local_version_complete");
if (state.pc == 0x802a8ad0) log_function("FUNCTION: btm_read_local_features_complete");
if (state.pc == 0x802a8fcc) log_function("FUNCTION: BTM_SetLocalDeviceName");
if (state.pc == 0x802a9084) log_function("FUNCTION: btm_read_local_name_complete");
if (state.pc == 0x802a9110) log_function("FUNCTION: BTM_ReadLocalDeviceAddr");
if (state.pc == 0x802a9150) log_function("FUNCTION: btm_read_local_addr_complete");
if (state.pc == 0x802a9198) log_function("FUNCTION: BTM_ReadLocalVersion");
if (state.pc == 0x802a91e4) log_function("FUNCTION: BTM_SetDeviceClass");
if (state.pc == 0x802a9264) log_function("FUNCTION: BTM_ReadDeviceClass");
if (state.pc == 0x802a9274) log_function("FUNCTION: BTM_ReadLocalFeatures");
if (state.pc == 0x802a9284) log_function("FUNCTION: BTM_RegisterForDeviceStatusNotif");
if (state.pc == 0x802a929c) log_function("FUNCTION: BTM_VendorSpecificCommand");
if (state.pc == 0x802a9398) log_function("FUNCTION: btm_vsc_complete");
if (state.pc == 0x802a9404) log_function("FUNCTION: BTM_RegisterForVSEvents");
if (state.pc == 0x802a943c) log_function("FUNCTION: btm_vendor_specific_evt");
if (state.pc == 0x802a94d4) log_function("FUNCTION: BTM_WritePageTimeout");
if (state.pc == 0x802a9574) log_function("FUNCTION: BTM_ReadStoredLinkKey");
if (state.pc == 0x802a964c) log_function("FUNCTION: BTM_WriteStoredLinkKey");
if (state.pc == 0x802a971c) log_function("FUNCTION: BTM_DeleteStoredLinkKey");
if (state.pc == 0x802a97ec) log_function("FUNCTION: btm_read_stored_link_key_complete");
if (state.pc == 0x802a9868) log_function("FUNCTION: btm_write_stored_link_key_complete");
if (state.pc == 0x802a98c4) log_function("FUNCTION: btm_delete_stored_link_key_complete");
if (state.pc == 0x802a992c) log_function("FUNCTION: btm_return_link_keys_evt");
if (state.pc == 0x802a9b50) log_function("FUNCTION: btm_discovery_db_reset");
if (state.pc == 0x802a9e90) log_function("FUNCTION: BTM_SetInquiryScanType");
if (state.pc == 0x802a9f40) log_function("FUNCTION: BTM_SetPageScanType");
if (state.pc == 0x802a9ff0) log_function("FUNCTION: BTM_SetInquiryMode");
if (state.pc == 0x802aa088) log_function("FUNCTION: BTM_SetConnectability");
if (state.pc == 0x802aa210) log_function("FUNCTION: BTM_IsInquiryActive");
if (state.pc == 0x802aa220) log_function("FUNCTION: BTM_CancelInquiry");
if (state.pc == 0x802aa328) log_function("FUNCTION: BTM_StartInquiry");
if (state.pc == 0x802aa4dc) log_function("FUNCTION: BTM_ReadRemoteDeviceName");
if (state.pc == 0x802aa5c4) log_function("FUNCTION: BTM_CancelRemoteDeviceName");
if (state.pc == 0x802aa63c) log_function("FUNCTION: BTM_InqDbRead");
if (state.pc == 0x802aa7b4) log_function("FUNCTION: BTM_InqDbNext");
if (state.pc == 0x802aa8f0) log_function("FUNCTION: BTM_ClearInqDb");
if (state.pc == 0x802aa9c0) log_function("FUNCTION: btm_inq_db_reset");
if (state.pc == 0x802aab5c) log_function("FUNCTION: btm_inq_find_bdaddr");
if (state.pc == 0x802aac38) log_function("FUNCTION: btm_inq_db_new");
if (state.pc == 0x802aad3c) log_function("FUNCTION: btm_set_inq_event_filter");
if (state.pc == 0x802aae20) log_function("FUNCTION: btm_event_filter_complete");
if (state.pc == 0x802ab040) log_function("FUNCTION: btm_process_inq_results");
if (state.pc == 0x802ab2b8) log_function("FUNCTION: btm_process_inq_complete");
if (state.pc == 0x802ab3bc) log_function("FUNCTION: btm_initiate_rem_name");
if (state.pc == 0x802ab50c) log_function("FUNCTION: btm_process_remote_name");
if (state.pc == 0x802ab7bc) log_function("FUNCTION: BTM_SetPowerMode");
if (state.pc == 0x802ab98c) log_function("FUNCTION: BTM_ReadPowerMode");
if (state.pc == 0x802aba44) log_function("FUNCTION: btm_pm_reset");
if (state.pc == 0x802ababc) log_function("FUNCTION: btm_pm_sm_alloc");
if (state.pc == 0x802abb0c) log_function("FUNCTION: btm_pm_compare_modes");
if (state.pc == 0x802abd28) log_function("FUNCTION: btm_pm_get_set_mode");
if (state.pc == 0x802abe88) log_function("FUNCTION: btm_pm_snd_md_req");
if (state.pc == 0x802ac0bc) log_function("FUNCTION: btm_pm_proc_cmd_status");
if (state.pc == 0x802ac3d8) log_function("FUNCTION: btm_esco_conn_rsp");
if (state.pc == 0x802ac5b4) log_function("FUNCTION: btm_sco_chk_pend_unpark");
if (state.pc == 0x802ac740) log_function("FUNCTION: btm_sco_conn_req");
if (state.pc == 0x802ac920) log_function("FUNCTION: btm_sco_connected");
if (state.pc == 0x802acac0) log_function("FUNCTION: BTM_RemoveSco");
if (state.pc == 0x802acb78) log_function("FUNCTION: btm_remove_sco_links");
if (state.pc == 0x802acbfc) log_function("FUNCTION: btm_sco_removed");
if (state.pc == 0x802acd10) log_function("FUNCTION: btm_sco_acl_removed");
if (state.pc == 0x802acdc8) log_function("FUNCTION: BTM_ChangeEScoLinkParms");
if (state.pc == 0x802acf70) log_function("FUNCTION: btm_esco_proc_conn_chg");
if (state.pc == 0x802ad074) log_function("FUNCTION: btm_is_sco_active");
if (state.pc == 0x802ad0e4) log_function("FUNCTION: btm_num_sco_links_active");
if (state.pc == 0x802ad244) log_function("FUNCTION: BTM_SecAddRmtNameNotifyCallback");
if (state.pc == 0x802ad294) log_function("FUNCTION: BTM_SecDeleteRmtNameNotifyCallback");
if (state.pc == 0x802ad2e8) log_function("FUNCTION: BTM_SetPinType");
if (state.pc == 0x802ad398) log_function("FUNCTION: BTM_SetSecurityLevel");
if (state.pc == 0x802ad5c0) log_function("FUNCTION: BTM_PINCodeReply");
if (state.pc == 0x802ad684) log_function("FUNCTION: BTM_DeviceAuthorized");
if (state.pc == 0x802ad860) log_function("FUNCTION: BTM_SecBond");
if (state.pc == 0x802adc2c) log_function("FUNCTION: btm_sec_l2cap_access_req");
if (state.pc == 0x802ae090) log_function("FUNCTION: btm_sec_mx_access_request");
if (state.pc == 0x802ae32c) log_function("FUNCTION: btm_sec_conn_req");
if (state.pc == 0x802ae458) log_function("FUNCTION: btm_sec_init");
if (state.pc == 0x802ae474) log_function("FUNCTION: btm_sec_dev_reset");
if (state.pc == 0x802ae4b4) log_function("FUNCTION: btm_sec_abort_access_req");
if (state.pc == 0x802ae568) log_function("FUNCTION: btm_sec_rmt_name_request_complete");
if (state.pc == 0x802ae850) log_function("FUNCTION: btm_sec_auth_complete");
if (state.pc == 0x802aeb94) log_function("FUNCTION: btm_sec_mkey_comp_event");
if (state.pc == 0x802aec90) log_function("FUNCTION: btm_sec_encrypt_change");
if (state.pc == 0x802aedcc) log_function("FUNCTION: btm_sec_is_bonding");
if (state.pc == 0x802af28c) log_function("FUNCTION: btm_sec_disconnect");
if (state.pc == 0x802af484) log_function("FUNCTION: btm_sec_link_key_notification");
if (state.pc == 0x802af630) log_function("FUNCTION: btm_sec_link_key_request");
if (state.pc == 0x802af760) log_function("FUNCTION: btm_sec_pin_code_request_timeout");
if (state.pc == 0x802af7d4) log_function("FUNCTION: btm_sec_pin_code_request");
if (state.pc == 0x802afb30) log_function("FUNCTION: btm_sec_update_clock_offset");
if (state.pc == 0x802afb80) log_function("FUNCTION: btm_sec_execute_procedure");
if (state.pc == 0x802aff60) log_function("FUNCTION: btm_sec_start_authorization");
if (state.pc == 0x802b007c) log_function("FUNCTION: btm_sec_collision_timeout");
if (state.pc == 0x802b0748) log_function("FUNCTION: btu_hcif_send_cmd");
if (state.pc == 0x802b08d4) log_function("FUNCTION: btu_hcif_connection_comp_evt");
if (state.pc == 0x802b09b0) log_function("FUNCTION: btu_hcif_connection_request_evt");
if (state.pc == 0x802b0a3c) log_function("FUNCTION: btu_hcif_qos_setup_comp_evt");
if (state.pc == 0x802b0b3c) log_function("FUNCTION: btu_hcif_esco_connection_comp_evt");
if (state.pc == 0x802b0c1c) log_function("FUNCTION: btu_hcif_hdl_command_complete");
if (state.pc == 0x802b0d74) log_function("FUNCTION: btu_hcif_command_complete_evt");
if (state.pc == 0x802b0e8c) log_function("FUNCTION: btu_hcif_hdl_command_status");
if (state.pc == 0x802b108c) log_function("FUNCTION: btu_hcif_command_status_evt");
if (state.pc == 0x802b11b4) log_function("FUNCTION: btu_hcif_cmd_timeout");
if (state.pc == 0x802b1418) log_function("FUNCTION: BTE_Init");
if (state.pc == 0x802b1614) log_function("FUNCTION: gap_connect_ind");
if (state.pc == 0x802b17a0) log_function("FUNCTION: gap_connect_cfm");
if (state.pc == 0x802b197c) log_function("FUNCTION: gap_config_ind");
if (state.pc == 0x802b1ab8) log_function("FUNCTION: gap_config_cfm");
if (state.pc == 0x802b1ca4) log_function("FUNCTION: gap_disconnect_ind");
if (state.pc == 0x802b1e9c) log_function("FUNCTION: gap_data_ind");
if (state.pc == 0x802b22d0) log_function("FUNCTION: gap_find_addr_name_cb");
if (state.pc == 0x802b24e8) log_function("FUNCTION: gap_find_addr_inq_cb");
if (state.pc == 0x802b27a4) log_function("FUNCTION: btsnd_hcic_inq_cancel");
if (state.pc == 0x802b2804) log_function("FUNCTION: btsnd_hcic_per_inq_mode");
if (state.pc == 0x802b28c4) log_function("FUNCTION: btsnd_hcic_create_conn");
if (state.pc == 0x802b29a4) log_function("FUNCTION: btsnd_hcic_disconnect");
if (state.pc == 0x802b2a2c) log_function("FUNCTION: btsnd_hcic_add_SCO_conn");
if (state.pc == 0x802b2ab8) log_function("FUNCTION: btsnd_hcic_accept_conn");
if (state.pc == 0x802b2b18) log_function("FUNCTION: btsnd_hcic_reject_conn");
if (state.pc == 0x802b2d14) log_function("FUNCTION: btsnd_hcic_link_key_neg_reply");
if (state.pc == 0x802b2db4) log_function("FUNCTION: btsnd_hcic_pin_code_req_reply");
if (state.pc == 0x802b2f98) log_function("FUNCTION: btsnd_hcic_pin_code_neg_reply");
if (state.pc == 0x802b3038) log_function("FUNCTION: btsnd_hcic_change_conn_type");
if (state.pc == 0x802b30c8) log_function("FUNCTION: btsnd_hcic_auth_request");
if (state.pc == 0x802b3144) log_function("FUNCTION: btsnd_hcic_set_conn_encrypt");
if (state.pc == 0x802b31d0) log_function("FUNCTION: btsnd_hcic_rmt_name_req");
if (state.pc == 0x802b32a8) log_function("FUNCTION: btsnd_hcic_rmt_name_req_cancel");
if (state.pc == 0x802b3348) log_function("FUNCTION: btsnd_hcic_rmt_features_req");
if (state.pc == 0x802b33c4) log_function("FUNCTION: btsnd_hcic_rmt_ver_req");
if (state.pc == 0x802b3440) log_function("FUNCTION: btsnd_hcic_read_rmt_clk_offset");
if (state.pc == 0x802b34bc) log_function("FUNCTION: btsnd_hcic_setup_esco_conn");
if (state.pc == 0x802b35b8) log_function("FUNCTION: btsnd_hcic_accept_esco_conn");
if (state.pc == 0x802b36a0) log_function("FUNCTION: btsnd_hcic_reject_esco_conn");
if (state.pc == 0x802b3700) log_function("FUNCTION: btsnd_hcic_hold_mode");
if (state.pc == 0x802b37b4) log_function("FUNCTION: btsnd_hcic_sniff_mode");
if (state.pc == 0x802b3880) log_function("FUNCTION: btsnd_hcic_exit_sniff_mode");
if (state.pc == 0x802b3904) log_function("FUNCTION: btsnd_hcic_park_mode");
if (state.pc == 0x802b39b8) log_function("FUNCTION: btsnd_hcic_exit_park_mode");
if (state.pc == 0x802b3a3c) log_function("FUNCTION: btsnd_hcic_switch_role");
if (state.pc == 0x802b3aec) log_function("FUNCTION: btsnd_hcic_write_policy_set");
if (state.pc == 0x802b3b80) log_function("FUNCTION: btsnd_hcic_reset");
if (state.pc == 0x802b3bdc) log_function("FUNCTION: btsnd_hcic_set_event_filter");
if (state.pc == 0x802b3d98) log_function("FUNCTION: btsnd_hcic_write_pin_type");
if (state.pc == 0x802b3e0c) log_function("FUNCTION: btsnd_hcic_read_stored_key");
if (state.pc == 0x802b3e6c) log_function("FUNCTION: btsnd_hcic_write_stored_key");
if (state.pc == 0x802b402c) log_function("FUNCTION: btsnd_hcic_delete_stored_key");
if (state.pc == 0x802b40dc) log_function("FUNCTION: btsnd_hcic_change_name");
if (state.pc == 0x802b421c) log_function("FUNCTION: btsnd_hcic_write_page_tout");
if (state.pc == 0x802b4254) log_function("FUNCTION: btsnd_hcic_write_scan_enable");
if (state.pc == 0x802b4284) log_function("FUNCTION: btsnd_hcic_write_pagescan_cfg");
if (state.pc == 0x802b42c8) log_function("FUNCTION: btsnd_hcic_write_inqscan_cfg");
if (state.pc == 0x802b430c) log_function("FUNCTION: btsnd_hcic_write_auth_enable");
if (state.pc == 0x802b4380) log_function("FUNCTION: btsnd_hcic_write_encr_mode");
if (state.pc == 0x802b43f4) log_function("FUNCTION: btsnd_hcic_write_dev_class");
if (state.pc == 0x802b4438) log_function("FUNCTION: btsnd_hcic_write_auto_flush_tout");
if (state.pc == 0x802b447c) log_function("FUNCTION: btsnd_hcic_set_host_buf_size");
if (state.pc == 0x802b4538) log_function("FUNCTION: btsnd_hcic_write_link_super_tout");
if (state.pc == 0x802b45cc) log_function("FUNCTION: btsnd_hcic_write_cur_iac_lap");
if (state.pc == 0x802b463c) log_function("FUNCTION: btsnd_hcic_read_local_ver");
if (state.pc == 0x802b469c) log_function("FUNCTION: btsnd_hcic_read_local_features");
if (state.pc == 0x802b46f8) log_function("FUNCTION: btsnd_hcic_read_buffer_size");
if (state.pc == 0x802b4720) log_function("FUNCTION: btsnd_hcic_read_bd_addr");
if (state.pc == 0x802b4780) log_function("FUNCTION: btsnd_hcic_get_link_quality");
if (state.pc == 0x802b47fc) log_function("FUNCTION: btsnd_hcic_read_rssi");
if (state.pc == 0x802b4874) log_function("FUNCTION: btsnd_hcic_set_afh_channels");
if (state.pc == 0x802b4c94) log_function("FUNCTION: btsnd_hcic_write_inqscan_type");
if (state.pc == 0x802b4cc4) log_function("FUNCTION: btsnd_hcic_write_inquiry_mode");
if (state.pc == 0x802b4cf4) log_function("FUNCTION: btsnd_hcic_write_pagescan_type");
if (state.pc == 0x802b4d24) log_function("FUNCTION: btsnd_hcic_vendor_spec_cmd");
if (state.pc == 0x802b4e18) log_function("FUNCTION: HID_DevInit");
if (state.pc == 0x802b4e80) log_function("FUNCTION: hidd_conn_initiate");
if (state.pc == 0x802b4f40) log_function("FUNCTION: hidd_proc_repage_timeout");
if (state.pc == 0x802b5008) log_function("FUNCTION: hidd_pm_set_now");
if (state.pc == 0x802b51e0) log_function("FUNCTION: hidd_pm_proc_mode_change");
if (state.pc == 0x802b5338) log_function("FUNCTION: hidd_pm_inact_timeout");
if (state.pc == 0x802b544c) log_function("FUNCTION: hidh_search_callback");
if (state.pc == 0x802b589c) log_function("FUNCTION: HID_HostInit");
if (state.pc == 0x802b58e0) log_function("FUNCTION: HID_HostRegister");
if (state.pc == 0x802b595c) log_function("FUNCTION: HID_HostDeregister");
if (state.pc == 0x802b5a40) log_function("FUNCTION: HID_HostAddDev");
if (state.pc == 0x802b5bd0) log_function("FUNCTION: HID_HostRemoveDev");
if (state.pc == 0x802b5c98) log_function("FUNCTION: HID_HostOpenDev");
if (state.pc == 0x802b5cfc) log_function("FUNCTION: HID_HostWriteDev");
if (state.pc == 0x802b5e3c) log_function("FUNCTION: HID_HostCloseDev");
if (state.pc == 0x802b625c) log_function("FUNCTION: hidh_conn_disconnect");
if (state.pc == 0x802b6300) log_function("FUNCTION: hidh_sec_check_complete_term");
if (state.pc == 0x802b6430) log_function("FUNCTION: hidh_l2cif_connect_ind");
if (state.pc == 0x802b6688) log_function("FUNCTION: hidh_proc_repage_timeout");
if (state.pc == 0x802b67d4) log_function("FUNCTION: hidh_sec_check_complete_orig");
if (state.pc == 0x802b69e8) log_function("FUNCTION: hidh_l2cif_connect_cfm");
if (state.pc == 0x802b6d30) log_function("FUNCTION: hidh_l2cif_config_ind");
if (state.pc == 0x802b6fd8) log_function("FUNCTION: hidh_l2cif_config_cfm");
if (state.pc == 0x802b72e4) log_function("FUNCTION: hidh_l2cif_disconnect_ind");
if (state.pc == 0x802b75a8) log_function("FUNCTION: hidh_l2cif_disconnect_cfm");
if (state.pc == 0x802b77f0) log_function("FUNCTION: hidh_l2cif_cong_ind");
if (state.pc == 0x802b79e8) log_function("FUNCTION: hidh_l2cif_data_ind");
if (state.pc == 0x802b801c) log_function("FUNCTION: hidh_conn_initiate");
if (state.pc == 0x802b8118) log_function("FUNCTION: hidd_conn_dereg");
if (state.pc == 0x802b82e0) log_function("FUNCTION: L2CA_Deregister");
if (state.pc == 0x802b8370) log_function("FUNCTION: L2CA_ConnectReq");
if (state.pc == 0x802b85a4) log_function("FUNCTION: L2CA_ConnectRsp");
if (state.pc == 0x802b8734) log_function("FUNCTION: L2CA_ConfigReq");
if (state.pc == 0x802b87ec) log_function("FUNCTION: L2CA_ConfigRsp");
if (state.pc == 0x802b88bc) log_function("FUNCTION: L2CA_DisconnectReq");
if (state.pc == 0x802b8960) log_function("FUNCTION: L2CA_DisconnectRsp");
if (state.pc == 0x802b8a04) log_function("FUNCTION: L2CA_DataWrite");
if (state.pc == 0x802b8b28) log_function("FUNCTION: L2CA_SetIdleTimeout");
if (state.pc == 0x802b8bf0) log_function("FUNCTION: L2CA_SetIdleTimeoutByBdAddr");
if (state.pc == 0x802b8cf0) log_function("FUNCTION: L2CA_SetTraceLevel");
if (state.pc == 0x802b8d5c) log_function("FUNCTION: l2c_csm_closed");
if (state.pc == 0x802b8ff0) log_function("FUNCTION: l2c_csm_orig_w4_sec_comp");
if (state.pc == 0x802b9160) log_function("FUNCTION: l2c_csm_term_w4_sec_comp");
if (state.pc == 0x802b92c8) log_function("FUNCTION: l2c_csm_w4_l2cap_connect_rsp");
if (state.pc == 0x802b950c) log_function("FUNCTION: l2c_csm_w4_l2ca_connect_rsp");
if (state.pc == 0x802b96e4) log_function("FUNCTION: l2c_csm_config");
if (state.pc == 0x802b9aac) log_function("FUNCTION: l2c_csm_open");
if (state.pc == 0x802b9d08) log_function("FUNCTION: l2c_csm_w4_l2cap_disconnect_rsp");
if (state.pc == 0x802b9eec) log_function("FUNCTION: l2c_csm_w4_l2ca_disconnect_rsp");
if (state.pc == 0x802ba340) log_function("FUNCTION: l2c_link_hci_conn_comp");
if (state.pc == 0x802ba578) log_function("FUNCTION: l2c_link_sec_comp");
if (state.pc == 0x802ba62c) log_function("FUNCTION: l2c_link_hci_disc_comp");
if (state.pc == 0x802ba6e8) log_function("FUNCTION: l2c_link_hci_qos_violation");
if (state.pc == 0x802ba758) log_function("FUNCTION: l2c_link_timeout");
if (state.pc == 0x802ba8cc) log_function("FUNCTION: l2c_link_send_to_lower");
if (state.pc == 0x802ba9d4) log_function("FUNCTION: l2c_link_check_send_pkts");
if (state.pc == 0x802baca0) log_function("FUNCTION: l2c_link_adjust_allocation");
if (state.pc == 0x802bae38) log_function("FUNCTION: l2c_link_process_num_completed_pkts");
if (state.pc == 0x802baf1c) log_function("FUNCTION: l2c_link_processs_num_bufs");
if (state.pc == 0x802baf30) log_function("FUNCTION: l2cap_link_chk_pkt_start");
if (state.pc == 0x802bb100) log_function("FUNCTION: l2cap_link_chk_pkt_end");
if (state.pc == 0x802bb16c) log_function("FUNCTION: l2c_link_role_changed");
if (state.pc == 0x802bb1ec) log_function("FUNCTION: l2c_link_role_change_failed");
if (state.pc == 0x802bb258) log_function("FUNCTION: l2c_link_segments_xmitted");
if (state.pc == 0x802bb48c) log_function("FUNCTION: l2c_rcv_acl_data");
if (state.pc == 0x802bb7bc) log_function("FUNCTION: process_l2cap_cmd");
if (state.pc == 0x802bc22c) log_function("FUNCTION: l2c_process_timeout");
if (state.pc == 0x802bc47c) log_function("FUNCTION: l2cu_release_lcb");
if (state.pc == 0x802bc57c) log_function("FUNCTION: l2cu_find_lcb_by_bd_addr");
if (state.pc == 0x802bc604) log_function("FUNCTION: l2cu_find_lcb_by_handle");
if (state.pc == 0x802bc6a4) log_function("FUNCTION: l2cu_build_header");
if (state.pc == 0x802bc768) log_function("FUNCTION: l2cu_send_peer_cmd_reject");
if (state.pc == 0x802bc864) log_function("FUNCTION: l2cu_send_peer_connect_req");
if (state.pc == 0x802bc928) log_function("FUNCTION: l2cu_send_peer_connect_rsp");
if (state.pc == 0x802bca00) log_function("FUNCTION: l2cu_reject_connection");
if (state.pc == 0x802bcac0) log_function("FUNCTION: l2cu_send_peer_config_req");
if (state.pc == 0x802bcdb8) log_function("FUNCTION: l2cu_send_peer_config_rsp");
if (state.pc == 0x802bd0b0) log_function("FUNCTION: l2cu_send_peer_config_rej");
if (state.pc == 0x802bd264) log_function("FUNCTION: l2cu_send_peer_disc_req");
if (state.pc == 0x802bd338) log_function("FUNCTION: l2cu_send_peer_disc_rsp");
if (state.pc == 0x802bd3f8) log_function("FUNCTION: l2cu_send_peer_echo_req");
if (state.pc == 0x802bd568) log_function("FUNCTION: l2cu_send_peer_echo_rsp");
if (state.pc == 0x802bd704) log_function("FUNCTION: l2cu_send_peer_info_rsp");
if (state.pc == 0x802bd7a8) log_function("FUNCTION: l2cu_allocate_ccb");
if (state.pc == 0x802bd8b4) log_function("FUNCTION: l2cu_release_ccb");
if (state.pc == 0x802bda58) log_function("FUNCTION: l2cu_find_ccb_by_cid");
if (state.pc == 0x802bdab4) log_function("FUNCTION: l2cu_allocate_rcb");
if (state.pc == 0x802bdb00) log_function("FUNCTION: l2cu_release_rcb");
if (state.pc == 0x802bdb10) log_function("FUNCTION: l2cu_find_rcb_by_psm");
if (state.pc == 0x802bdbc8) log_function("FUNCTION: l2cu_process_peer_cfg_req");
if (state.pc == 0x802bdd10) log_function("FUNCTION: l2cu_process_peer_cfg_rsp");
if (state.pc == 0x802bdd50) log_function("FUNCTION: l2cu_process_our_cfg_req");
if (state.pc == 0x802bde60) log_function("FUNCTION: l2cu_process_our_cfg_rsp");
if (state.pc == 0x802bdea0) log_function("FUNCTION: l2cu_device_reset");
if (state.pc == 0x802bdf0c) log_function("FUNCTION: l2cu_create_conn");
if (state.pc == 0x802be024) log_function("FUNCTION: l2cu_create_conn_after_switch");
if (state.pc == 0x802be0f4) log_function("FUNCTION: l2cu_find_lcb_by_state");
if (state.pc == 0x802be184) log_function("FUNCTION: l2cu_lcb_disconnecting");
if (state.pc == 0x802be26c) log_function("FUNCTION: RFCOMM_Init");
if (state.pc == 0x802be2bc) log_function("FUNCTION: PORT_StartCnf");
if (state.pc == 0x802be41c) log_function("FUNCTION: PORT_StartInd");
if (state.pc == 0x802be4b8) log_function("FUNCTION: PORT_ParNegInd");
if (state.pc == 0x802be668) log_function("FUNCTION: PORT_ParNegCnf");
if (state.pc == 0x802be76c) log_function("FUNCTION: PORT_DlcEstablishInd");
if (state.pc == 0x802be8ac) log_function("FUNCTION: PORT_DlcEstablishCnf");
if (state.pc == 0x802be9f0) log_function("FUNCTION: PORT_PortNegInd");
if (state.pc == 0x802beb40) log_function("FUNCTION: PORT_PortNegCnf");
if (state.pc == 0x802bef5c) log_function("FUNCTION: PORT_DlcReleaseInd");
if (state.pc == 0x802befc4) log_function("FUNCTION: PORT_CloseInd");
if (state.pc == 0x802bf064) log_function("FUNCTION: Port_TimeOutCloseMux");
if (state.pc == 0x802bf0fc) log_function("FUNCTION: PORT_DataInd");
if (state.pc == 0x802bf2fc) log_function("FUNCTION: PORT_FlowInd");
if (state.pc == 0x802bf42c) log_function("FUNCTION: port_rfc_send_tx_data");
if (state.pc == 0x802bf6b8) log_function("FUNCTION: port_select_mtu");
if (state.pc == 0x802bf834) log_function("FUNCTION: port_release_port");
if (state.pc == 0x802bf910) log_function("FUNCTION: port_find_mcb_dlci_port");
if (state.pc == 0x802bf964) log_function("FUNCTION: port_find_dlci_port");
if (state.pc == 0x802bf9ec) log_function("FUNCTION: port_flow_control_user");
if (state.pc == 0x802bfa5c) log_function("FUNCTION: port_get_signal_changes");
if (state.pc == 0x802bfd0c) log_function("FUNCTION: RFCOMM_ConnectInd");
if (state.pc == 0x802bfd98) log_function("FUNCTION: RFCOMM_ConnectCnf");
if (state.pc == 0x802bfe9c) log_function("FUNCTION: RFCOMM_ConfigInd");
if (state.pc == 0x802bffa4) log_function("FUNCTION: RFCOMM_ConfigCnf");
if (state.pc == 0x802c00b0) log_function("FUNCTION: RFCOMM_DisconnectInd");
if (state.pc == 0x802c01d4) log_function("FUNCTION: RFCOMM_BufDataInd");
if (state.pc == 0x802c0474) log_function("FUNCTION: RFCOMM_CongestionStatusInd");
if (state.pc == 0x802c0608) log_function("FUNCTION: rfc_mx_sm_state_idle");
if (state.pc == 0x802c081c) log_function("FUNCTION: rfc_mx_sm_state_wait_conn_cnf");
if (state.pc == 0x802c09d8) log_function("FUNCTION: rfc_mx_sm_state_configure");
if (state.pc == 0x802c0b00) log_function("FUNCTION: rfc_mx_sm_sabme_wait_ua");
if (state.pc == 0x802c0c74) log_function("FUNCTION: rfc_mx_sm_state_wait_sabme");
if (state.pc == 0x802c0d94) log_function("FUNCTION: rfc_mx_sm_state_connected");
if (state.pc == 0x802c0eac) log_function("FUNCTION: rfc_mx_sm_state_disc_wait_ua");
if (state.pc == 0x802c1024) log_function("FUNCTION: rfc_mx_conf_cnf");
if (state.pc == 0x802c1298) log_function("FUNCTION: rfc_port_sm_state_closed");
if (state.pc == 0x802c140c) log_function("FUNCTION: rfc_port_sm_sabme_wait_ua");
if (state.pc == 0x802c15a8) log_function("FUNCTION: rfc_port_sm_term_wait_sec_check");
if (state.pc == 0x802c1764) log_function("FUNCTION: rfc_port_sm_orig_wait_sec_check");
if (state.pc == 0x802c18b4) log_function("FUNCTION: rfc_port_sm_opened");
if (state.pc == 0x802c1aa0) log_function("FUNCTION: rfc_port_sm_disc_wait_ua");
if (state.pc == 0x802c1bbc) log_function("FUNCTION: rfc_process_pn");
if (state.pc == 0x802c1ca4) log_function("FUNCTION: rfc_process_rpn");
if (state.pc == 0x802c1fb0) log_function("FUNCTION: rfc_process_msc");
if (state.pc == 0x802c211c) log_function("FUNCTION: rfc_process_rls");
if (state.pc == 0x802c21b4) log_function("FUNCTION: rfc_process_fcon");
if (state.pc == 0x802c2218) log_function("FUNCTION: rfc_process_fcoff");
if (state.pc == 0x802c2304) log_function("FUNCTION: rfc_set_port_state");
if (state.pc == 0x802c23a8) log_function("FUNCTION: RFCOMM_StartRsp");
if (state.pc == 0x802c23d4) log_function("FUNCTION: RFCOMM_DlcEstablishReq");
if (state.pc == 0x802c243c) log_function("FUNCTION: RFCOMM_DlcEstablishRsp");
if (state.pc == 0x802c24ac) log_function("FUNCTION: RFCOMM_ParNegReq");
if (state.pc == 0x802c258c) log_function("FUNCTION: RFCOMM_ParNegRsp");
if (state.pc == 0x802c2690) log_function("FUNCTION: RFCOMM_ControlReq");
if (state.pc == 0x802c2734) log_function("FUNCTION: RFCOMM_FlowReq");
if (state.pc == 0x802c27d8) log_function("FUNCTION: RFCOMM_LineStatusReq");
if (state.pc == 0x802c2870) log_function("FUNCTION: RFCOMM_DlcReleaseReq");
if (state.pc == 0x802c2984) log_function("FUNCTION: rfc_send_ua");
if (state.pc == 0x802c2a34) log_function("FUNCTION: rfc_send_dm");
if (state.pc == 0x802c2af8) log_function("FUNCTION: rfc_send_disc");
if (state.pc == 0x802c2ba8) log_function("FUNCTION: rfc_send_buf_uih");
if (state.pc == 0x802c2d40) log_function("FUNCTION: rfc_send_pn");
if (state.pc == 0x802c2e28) log_function("FUNCTION: rfc_send_fcon");
if (state.pc == 0x802c2eac) log_function("FUNCTION: rfc_send_fcoff");
if (state.pc == 0x802c2f30) log_function("FUNCTION: rfc_send_msc");
if (state.pc == 0x802c3050) log_function("FUNCTION: rfc_send_rls");
if (state.pc == 0x802c3100) log_function("FUNCTION: rfc_send_rpn");
if (state.pc == 0x802c321c) log_function("FUNCTION: rfc_send_test");
if (state.pc == 0x802c32c4) log_function("FUNCTION: rfc_send_credit");
if (state.pc == 0x802c3384) log_function("FUNCTION: rfc_parse_data");
if (state.pc == 0x802c3f54) log_function("FUNCTION: rfc_check_fcs");
if (state.pc == 0x802c3fa0) log_function("FUNCTION: rfc_alloc_multiplexer_channel");
if (state.pc == 0x802c40f8) log_function("FUNCTION: rfc_release_multiplexer_channel");
if (state.pc == 0x802c4180) log_function("FUNCTION: rfc_timer_start");
if (state.pc == 0x802c41f4) log_function("FUNCTION: rfc_timer_stop");
if (state.pc == 0x802c424c) log_function("FUNCTION: rfc_port_timer_start");
if (state.pc == 0x802c42cc) log_function("FUNCTION: rfc_port_timer_stop");
if (state.pc == 0x802c4324) log_function("FUNCTION: rfc_check_mcb_active");
if (state.pc == 0x802c43e8) log_function("FUNCTION: rfcomm_process_timeout");
if (state.pc == 0x802c4424) log_function("FUNCTION: rfc_sec_check_complete");
if (state.pc == 0x802c4478) log_function("FUNCTION: rfc_port_closed");
if (state.pc == 0x802c45d0) log_function("FUNCTION: rfc_inc_credit");
if (state.pc == 0x802c465c) log_function("FUNCTION: rfc_dec_credit");
if (state.pc == 0x802c4a74) log_function("FUNCTION: SDP_ServiceSearchRequest");
if (state.pc == 0x802c4ad0) log_function("FUNCTION: SDP_ServiceSearchAttributeRequest");
if (state.pc == 0x802c4b5c) log_function("FUNCTION: SDP_FindServiceInDb");
if (state.pc == 0x802c4c28) log_function("FUNCTION: SDP_FindServiceUUIDInDb");
if (state.pc == 0x802c5090) log_function("FUNCTION: SDP_GetLocalDiRecord");
if (state.pc == 0x802c56a0) log_function("FUNCTION: find_uuid_in_seq");
if (state.pc == 0x802c5778) log_function("FUNCTION: sdp_db_find_record");
if (state.pc == 0x802c57d4) log_function("FUNCTION: sdp_db_find_attr_in_rec");
if (state.pc == 0x802c5814) log_function("FUNCTION: SDP_CreateRecord");
if (state.pc == 0x802c58f4) log_function("FUNCTION: SDP_DeleteRecord");
if (state.pc == 0x802c5a08) log_function("FUNCTION: SDP_AddAttribute");
if (state.pc == 0x802c5da0) log_function("FUNCTION: SDP_AddUuidSequence");
if (state.pc == 0x802c5e78) log_function("FUNCTION: SDP_AddServiceClassIdList");
if (state.pc == 0x802c6230) log_function("FUNCTION: sdpu_build_uuid_seq");
if (state.pc == 0x802c644c) log_function("FUNCTION: sdp_disc_connected");
if (state.pc == 0x802c6480) log_function("FUNCTION: sdp_disc_server_rsp");
if (state.pc == 0x802c65c0) log_function("FUNCTION: process_service_search_rsp");
if (state.pc == 0x802c6708) log_function("FUNCTION: process_service_attr_rsp");
if (state.pc == 0x802c69b0) log_function("FUNCTION: process_service_search_attr_rsp");
if (state.pc == 0x802c6c84) log_function("FUNCTION: save_attr_seq");
if (state.pc == 0x802c6e70) log_function("FUNCTION: add_record");
if (state.pc == 0x802c789c) log_function("FUNCTION: sdp_config_ind");
if (state.pc == 0x802c7b54) log_function("FUNCTION: sdp_disconnect_ind");
if (state.pc == 0x802c7c4c) log_function("FUNCTION: sdp_data_ind");
if (state.pc == 0x802c7ed0) log_function("FUNCTION: sdp_disconnect_cfm");
if (state.pc == 0x802c8168) log_function("FUNCTION: process_service_search");
if (state.pc == 0x802c8db4) log_function("FUNCTION: sdpu_allocate_ccb");
if (state.pc == 0x802c8e28) log_function("FUNCTION: sdpu_release_ccb");
if (state.pc == 0x802c8e60) log_function("FUNCTION: sdpu_build_attrib_seq");
if (state.pc == 0x802c9030) log_function("FUNCTION: sdpu_build_attrib_entry");
if (state.pc == 0x802c9184) log_function("FUNCTION: sdpu_build_n_send_error");
if (state.pc == 0x802c92c0) log_function("FUNCTION: sdpu_extract_uid_seq");
if (state.pc == 0x802c9610) log_function("FUNCTION: sdpu_extract_attr_seq");
if (state.pc == 0x802c9860) log_function("FUNCTION: sdpu_get_len_from_type");
if (state.pc == 0x802c9930) log_function("FUNCTION: sdpu_is_base_uuid");
if (state.pc == 0x802c9a10) log_function("FUNCTION: sdpu_compare_uuid_arrays");
if (state.pc == 0x802c9d14) log_function("FUNCTION: sdpu_sort_attr_list");
if (state.pc == 0x802c9d64) {
     log_function("FUNCTION: USB_LOG %x", state.lr);
    
    // hle
                hle_os_report(cast(void*) &mem, &state);

}
if (state.pc == 0x802c9e0c) {
    log_function("FUNCTION: USB_ERR");
    hle_os_report(cast(void*) &mem, &state);
}
if (state.pc == 0x802c9f90) log_function("FUNCTION: GetNumNode__Q34nw4r3g3d9ResAnmVisCFv");
if (state.pc == 0x802cda9c) log_function("FUNCTION: WPADiRetrieveChannel");
if (state.pc == 0x802cdfe0) log_function("FUNCTION: WPADiRecvCallback");
if (state.pc == 0x802ce7b8) log_function("FUNCTION: WPADSaveConfig");
if (state.pc == 0x802d0458) log_function("FUNCTION: WPADSetSpeakerVolume");
if (state.pc == 0x802d1da8) log_function("FUNCTION: WPADiSendWriteDataCmd");
if (state.pc == 0x802d1f5c) log_function("FUNCTION: WPADiSendWriteData");
if (state.pc == 0x802d2114) log_function("FUNCTION: WPADiSendReadData");
if (state.pc == 0x802d22c0) log_function("FUNCTION: WPADiClearQueue");
if (state.pc == 0x802d3300) log_function("FUNCTION: WPADiHIDParser");
if (state.pc == 0x802d7bb4) log_function("FUNCTION: App_MEMfree");
if (state.pc == 0x802d7c04) log_function("FUNCTION: SyncFlushCallback");
if (state.pc == 0x802d7c7c) log_function("FUNCTION: DeleteFlushCallback");
if (state.pc == 0x802d7e98) log_function("FUNCTION: WUDiSaveDeviceToNand");
if (state.pc == 0x802d89fc) log_function("FUNCTION: WUDiDeleteDevice");
if (state.pc == 0x802d95d8) log_function("FUNCTION: WUDRegisterAllocator");
if (state.pc == 0x802d97ec) log_function("FUNCTION: WUDGetBufferStatus");
if (state.pc == 0x802d9834) log_function("FUNCTION: WUDSetSniffMode");
if (state.pc == 0x802d98a0) log_function("FUNCTION: WUDSetSyncSimpleCallback");
if (state.pc == 0x802d9abc) log_function("FUNCTION: WUDStopSyncSimple");
if (state.pc == 0x802d9b54) log_function("FUNCTION: WUDSetDisableChannel");
if (state.pc == 0x802d9c40) log_function("FUNCTION: WUDSetHidRecvCallback");
if (state.pc == 0x802d9c9c) log_function("FUNCTION: WUDSetHidConnCallback");
if (state.pc == 0x802d9cf8) log_function("FUNCTION: WUDSetVisibility");
if (state.pc == 0x802da560) log_function("FUNCTION: WUDiGetDevInfo");
if (state.pc == 0x802da638) log_function("FUNCTION: WUDiGetNewDevInfo");
if (state.pc == 0x802da6f8) log_function("FUNCTION: WUDiMoveTopSmpDevInfoPtr");
if (state.pc == 0x802da810) log_function("FUNCTION: WUDiMoveBottomSmpDevInfoPtr");
if (state.pc == 0x802da928) log_function("FUNCTION: WUDiMoveTopOfDisconnectedSmpDevice");
if (state.pc == 0x802daa80) log_function("FUNCTION: WUDiMoveTopStdDevInfoPtr");
if (state.pc == 0x802dab98) log_function("FUNCTION: WUDiMoveBottomStdDevInfoPtr");
if (state.pc == 0x802dacb0) log_function("FUNCTION: WUDiMoveTopOfDisconnectedStdDevice");
if (state.pc == 0x802dae08) log_function("FUNCTION: CleanupCallback");
if (state.pc == 0x802dbce4) log_function("FUNCTION: _WUDGetDevAddr");
if (state.pc == 0x802dc314) log_function("FUNCTION: bta_hh_co_data");
if (state.pc == 0x802dc4dc) log_function("FUNCTION: reset_kpad");
if (state.pc == 0x802dc824) log_function("FUNCTION: calc_button_repeat");
if (state.pc == 0x802dc9b8) log_function("FUNCTION: calc_acc_horizon");
if (state.pc == 0x802dcb4c) log_function("FUNCTION: calc_acc_vertical");
if (state.pc == 0x802dd278) log_function("FUNCTION: select_2obj_first");
if (state.pc == 0x802dd460) log_function("FUNCTION: select_2obj_continue");
if (state.pc == 0x802dd688) log_function("FUNCTION: select_1obj_first");
if (state.pc == 0x802dd83c) log_function("FUNCTION: select_1obj_continue");
if (state.pc == 0x802ddd98) log_function("FUNCTION: read_kpad_dpd");
if (state.pc == 0x802de318) log_function("FUNCTION: clamp_stick_cross");
if (state.pc == 0x802de53c) log_function("FUNCTION: read_kpad_stick");
if (state.pc == 0x802df690) log_function("FUNCTION: CXGetUncompressedSize");
if (state.pc == 0x802df804) log_function("FUNCTION: CXGetCompressionHeader");
if (state.pc == 0x802df90c) log_function("FUNCTION: ARCOpen");
if (state.pc == 0x802dfbb0) log_function("FUNCTION: ARCFastOpen");
if (state.pc == 0x802dfc00) log_function("FUNCTION: ARCConvertPathToEntrynum");
if (state.pc == 0x802dfe64) log_function("FUNCTION: entryToPath");
if (state.pc == 0x802e002c) log_function("FUNCTION: ARCGetStartAddrInMem");
if (state.pc == 0x802e0050) log_function("FUNCTION: ARCChangeDir");
if (state.pc == 0x802e0124) log_function("FUNCTION: ARCReadDir");
if (state.pc == 0x802e02f8) log_function("FUNCTION: TPLGet");
if (state.pc == 0x802e0318) log_function("FUNCTION: TPLGetGXTexObjFromPalette");
if (state.pc == 0x802e059c) log_function("FUNCTION: PADOriginCallback");
if (state.pc == 0x802e065c) log_function("FUNCTION: PADProbeCallback");
if (state.pc == 0x802e0730) log_function("FUNCTION: PADTypeAndStatusCallback");
if (state.pc == 0x802e0a50) log_function("FUNCTION: PADReset");
if (state.pc == 0x802e0c64) log_function("FUNCTION: PADInit");
if (state.pc == 0x802e0dc0) log_function("FUNCTION: SPEC0_MakeStatus");
if (state.pc == 0x802e0ed8) log_function("FUNCTION: SPEC1_MakeStatus");
if (state.pc == 0x802e1570) log_function("FUNCTION: OnShutdown");
if (state.pc == 0x802e1638) log_function("FUNCTION: SamplingHandler");
if (state.pc == 0x802e1698) log_function("FUNCTION: __PADDisableRecalibration");
if (state.pc == 0x802e2260) log_function("FUNCTION: Skip__Q44nw4r2ut10FileStream12FilePositionFl");
if (state.pc == 0x802e22c4) log_function("FUNCTION: Seek__Q44nw4r2ut10FileStream12FilePositionFlUl");
if (state.pc == 0x802e2370) log_function("FUNCTION: DvdAsyncCallback___Q34nw4r2ut13DvdFileStreamFlP11DVDFileInfo");
if (state.pc == 0x802e239c) log_function("FUNCTION: DvdCBAsyncCallback___Q34nw4r2ut13DvdFileStreamFlP15DVDCommandBlock");
if (state.pc == 0x802e2480) log_function("FUNCTION: __ct__Q34nw4r2ut13DvdFileStreamFPC11DVDFileInfob");
if (state.pc == 0x802e25b0) log_function("FUNCTION: __dt__Q34nw4r2ut13DvdFileStreamFv");
if (state.pc == 0x802e2628) log_function("FUNCTION: Close__Q34nw4r2ut13DvdFileStreamFv");
if (state.pc == 0x802e2678) log_function("FUNCTION: Read__Q34nw4r2ut13DvdFileStreamFPvUl");
if (state.pc == 0x802e2700) log_function("FUNCTION: ReadAsync__Q34nw4r2ut13DvdFileStreamFPvUlPFlPQ34nw4r2ut8IOStreamPv_vPv");
if (state.pc == 0x802e2830) log_function("FUNCTION: PeekAsync__Q34nw4r2ut13DvdFileStreamFPvUlPFlPQ34nw4r2ut8IOStreamPv_vPv");
if (state.pc == 0x802e28c0) log_function("FUNCTION: CancelAsync__Q34nw4r2ut13DvdFileStreamFPFlPQ34nw4r2ut8IOStreamPv_vPv");
if (state.pc == 0x802e296c) log_function("FUNCTION: IsBusy__Q34nw4r2ut13DvdFileStreamCFv");
if (state.pc == 0x802e2d58) log_function("FUNCTION: SBServerGetFlags");
if (state.pc == 0x802e2e30) log_function("FUNCTION: SetAlternateChar__Q46nw4hbm2ut6detail11ResFontBaseFUs");
if (state.pc == 0x802e2f20) log_function("FUNCTION: GetCharWidths__Q46nw4hbm2ut6detail11ResFontBaseCFUs");
if (state.pc == 0x802e300c) log_function("FUNCTION: GetGlyph__Q46nw4hbm2ut6detail11ResFontBaseCFPQ36nw4hbm2ut5GlyphUs");
if (state.pc == 0x802e3114) log_function("FUNCTION: SBServerGetPrivateQueryPort");
if (state.pc == 0x802e3190) log_function("FUNCTION: GetGlyphFromIndex__Q46nw4hbm2ut6detail11ResFontBaseCFPQ36nw4hbm2ut5GlyphUs");
if (state.pc == 0x802e3328) log_function("FUNCTION: SetResource__Q36nw4hbm2ut7ResFontFPv");
if (state.pc == 0x802e35d8) log_function("FUNCTION: __ct__Q34nw4r2ut10CharWriterFv");
if (state.pc == 0x802e39dc) log_function("FUNCTION: SetupGX__Q34nw4r2ut10CharWriterFv");
if (state.pc == 0x802e4434) log_function("FUNCTION: SetFontSize__Q34nw4r2ut10CharWriterFff");
if (state.pc == 0x802e44f8) log_function("FUNCTION: GetFontWidth__Q34nw4r2ut10CharWriterCFv");
if (state.pc == 0x802e4558) log_function("FUNCTION: GetFontHeight__Q34nw4r2ut10CharWriterCFv");
if (state.pc == 0x802e45b8) log_function("FUNCTION: GetFontAscent__Q34nw4r2ut10CharWriterCFv");
if (state.pc == 0x802e4618) log_function("FUNCTION: Print__Q34nw4r2ut10CharWriterFUs");
if (state.pc == 0x802e4748) log_function("FUNCTION: PrintGlyph__Q34nw4r2ut10CharWriterFfffRCQ34nw4r2ut5Glyph");
if (state.pc == 0x802e4b14) log_function("FUNCTION: SetupGXWithColorMapping__Q34nw4r2ut10CharWriterFQ34nw4r2ut5ColorQ34nw4r2ut5Color");
if (state.pc == 0x802e664c) log_function("FUNCTION: Log__Q34nw4r2db6detailFPCce");
if (state.pc == 0x802e66e4) log_function("FUNCTION: ShowStack___Q24nw4r2dbFUl");
if (state.pc == 0x802e6884) log_function("FUNCTION: STD_TSNPrintf");
if (state.pc == 0x802e7314) log_function("FUNCTION: BindAnimation__Q36nw4hbm3lyt4PaneFPQ36nw4hbm3lyt13AnimTransformb");
if (state.pc == 0x802e73d8) log_function("FUNCTION: UnbindAnimationSelf__Q36nw4hbm3lyt4PaneFPQ36nw4hbm3lyt13AnimTransform");
if (state.pc == 0x802e74ac) log_function("FUNCTION: FindAnimationLink__Q36nw4hbm3lyt4PaneFPQ36nw4hbm3lyt13AnimTransform");
if (state.pc == 0x802e7524) log_function("FUNCTION: SetAnimationEnable__Q36nw4hbm3lyt4PaneFPQ36nw4hbm3lyt13AnimTransformbb");
if (state.pc == 0x802e8288) log_function("FUNCTION: BindAnimation__Q36nw4hbm3lyt6LayoutFPQ36nw4hbm3lyt13AnimTransform");
if (state.pc == 0x802e82d0) log_function("FUNCTION: UnbindAllAnimation__Q36nw4hbm3lyt6LayoutFv");
if (state.pc == 0x802e82e4) log_function("FUNCTION: SetAnimationEnable__Q36nw4hbm3lyt6LayoutFPQ36nw4hbm3lyt13AnimTransformb");
if (state.pc == 0x802e8334) log_function("FUNCTION: Update__Q34nw4r2dw6WindowFv");
if (state.pc == 0x802e8374) log_function("FUNCTION: GetLayoutRect__Q34nw4r3lyt6LayoutCFv");
if (state.pc == 0x802e8b28) log_function("FUNCTION: GetVtxColor__Q36nw4hbm3lyt7PictureCFUl");
if (state.pc == 0x802e8b54) log_function("FUNCTION: SetVtxColor__Q36nw4hbm3lyt7PictureFUlQ36nw4hbm2ut5Color");
if (state.pc == 0x802e8b80) log_function("FUNCTION: GetVtxColorElement__Q36nw4hbm3lyt7PictureCFUl");
if (state.pc == 0x802e8b98) log_function("FUNCTION: SetVtxColorElement__Q36nw4hbm3lyt7PictureFUlUc");
if (state.pc == 0x802e9224) log_function("FUNCTION: GetVtxColorElement__Q36nw4hbm3lyt7TextBoxCFUl");
if (state.pc == 0x802e923c) log_function("FUNCTION: SetVtxColorElement__Q36nw4hbm3lyt7TextBoxFUlUc");
if (state.pc == 0x802e9788) log_function("FUNCTION: SetTextColor__Q34nw4r2ut10CharWriterFQ34nw4r2ut5ColorQ34nw4r2ut5Color");
if (state.pc == 0x802e9c6c) log_function("FUNCTION: SetString__Q36nw4hbm3lyt7TextBoxFPCwUs");
if (state.pc == 0x802e9cd4) log_function("FUNCTION: SetString__Q36nw4hbm3lyt7TextBoxFPCwUsUs");
if (state.pc == 0x802ea0b4) log_function("FUNCTION: CalcStringRectImpl<w>__Q34nw4r3lyt25@unnamed@lyt_textBox_cpp@FPQ34nw4r2ut4RectPQ34nw4r2ut17TextWriterBase<w>PCwif_v");
if (state.pc == 0x802ea668) log_function("FUNCTION: FindAnimationLink__Q36nw4hbm3lyt6WindowFPQ36nw4hbm3lyt13AnimTransform");
if (state.pc == 0x802ea70c) log_function("FUNCTION: SetAnimationEnable__Q36nw4hbm3lyt6WindowFPQ36nw4hbm3lyt13AnimTransformbb");
if (state.pc == 0x802ea7a0) log_function("FUNCTION: GetVtxColor__Q36nw4hbm3lyt6WindowCFUl");
if (state.pc == 0x802ea7cc) log_function("FUNCTION: SetVtxColor__Q36nw4hbm3lyt6WindowFUlQ36nw4hbm2ut5Color");
if (state.pc == 0x802ea7f8) log_function("FUNCTION: GetVtxColorElement__Q36nw4hbm3lyt6WindowCFUl");
if (state.pc == 0x802ea810) log_function("FUNCTION: SetVtxColorElement__Q36nw4hbm3lyt6WindowFUlUc");
if (state.pc == 0x802ea9f8) log_function("FUNCTION: UnbindAnimationSelf__Q36nw4hbm3lyt6WindowFPQ36nw4hbm3lyt13AnimTransform");
if (state.pc == 0x802eaa88) log_function("FUNCTION: DrawContent__Q36nw4hbm3lyt6WindowFRCQ36nw4hbm4math4VEC2RCQ36nw4hbm3lyt15WindowFrameSizeUc");
if (state.pc == 0x802ec64c) log_function("FUNCTION: GetFrameMaterial__Q36nw4hbm3lyt6WindowCFUl");
if (state.pc == 0x802ec674) log_function("FUNCTION: GetContentMaterial__Q36nw4hbm3lyt6WindowCFv");
if (state.pc == 0x802ec84c) log_function("FUNCTION: SetIndTexMtx__Q34nw4r3lyt26@unnamed@lyt_material_cpp@F14_GXIndTexMtxIDPA3_Cf");
if (state.pc == 0x802eda84) log_function("FUNCTION: __dt__Q34nw4r3lyt8MaterialFv");
if (state.pc == 0x802edb30) log_function("FUNCTION: ReserveGXMem__Q34nw4r3lyt8MaterialFUcUcUcUcbUcUcbbbb");
if (state.pc == 0x802ee454) log_function("FUNCTION: SetColorElement__Q34nw4r3lyt8MaterialFUls");
if (state.pc == 0x802efb90) log_function("FUNCTION: GetHermiteCurveValue__Q34nw4r3lyt27@unnamed@lyt_animation_cpp@FfPCQ44nw4r3lyt3res10HermiteKeyUl");
if (state.pc == 0x802efd58) log_function("FUNCTION: __ct__Q34nw4r3lyt18AnimTransformBasicFv");
if (state.pc == 0x802efd8c) log_function("FUNCTION: __dt__Q34nw4r3lyt18AnimTransformBasicFv");
if (state.pc == 0x802eff50) log_function("FUNCTION: Bind__Q36nw4hbm3lyt18AnimTransformBasicFPQ36nw4hbm3lyt4Paneb");
if (state.pc == 0x802f03ec) log_function("FUNCTION: OnChangeOutputMode__Q34nw4r3snd6FxBaseFv");
if (state.pc == 0x802f0770) log_function("FUNCTION: GetResourceSub__37@unnamed@lyt_arcResourceAccessor_cpp@FP9ARCHandlePCcUlPCcPUl");
if (state.pc == 0x802f0a18) log_function("FUNCTION: TestFileHeader__Q36nw4hbm3lyt6detailFRCQ46nw4hbm3lyt3res16BinaryFileHeader");
if (state.pc == 0x802f0a40) log_function("FUNCTION: TestFileHeader__Q36nw4hbm3lyt6detailFRCQ46nw4hbm3lyt3res16BinaryFileHeaderUl");
if (state.pc == 0x802f0b54) log_function("FUNCTION: SetSize__Q44nw4r3lyt6detail11TexCoordAryFUc");
if (state.pc == 0x802f0e74) log_function("FUNCTION: DrawQuad__Q36nw4hbm3lyt6detailFRCQ36nw4hbm4math4VEC2RCQ36nw4hbm3lyt4SizeUcPA4_CQ36nw4hbm4math4VEC2PCQ36nw4hbm2ut5Color");
if (state.pc == 0x802f1594) log_function("FUNCTION: Atan2FIdx__Q24nw4r4mathFff");
if (state.pc == 0x802f1c54) log_function("FUNCTION: GetInstance__Q44nw4r3snd6detail9AxManagerFv");
if (state.pc == 0x802f1cb8) log_function("FUNCTION: __dt__Q44nw4r3snd6detail9AxManagerFv");
if (state.pc == 0x802f1d30) log_function("FUNCTION: Init__Q44nw4r3snd6detail9AxManagerFv");
if (state.pc == 0x802f1e04) log_function("FUNCTION: GetOutputVolume__Q44nw4r3snd6detail9AxManagerCFv");
if (state.pc == 0x802f22a4) log_function("FUNCTION: RegisterCallback__Q44nw4r3snd6detail9AxManagerFPQ54nw4r3snd6detail9AxManager16CallbackListNodePFv_v");
if (state.pc == 0x802f2310) log_function("FUNCTION: UnregisterCallback__Q44nw4r3snd6detail9AxManagerFPQ54nw4r3snd6detail9AxManager16CallbackListNode");
if (state.pc == 0x802f23f0) log_function("FUNCTION: SetMasterVolume__Q44nw4r3snd6detail9AxManagerFfi");
if (state.pc == 0x802f2628) log_function("FUNCTION: AppendEffect__Q44nw4r3snd6detail9AxManagerFQ34nw4r3snd6AuxBusPQ34nw4r3snd6FxBase");
if (state.pc == 0x802f282c) log_function("FUNCTION: ClearEffect__Q44nw4r3snd6detail9AxManagerFQ34nw4r3snd6AuxBusi");
if (state.pc == 0x802f2cb4) log_function("FUNCTION: PrepareReset__Q44nw4r3snd6detail9AxManagerFv");
if (state.pc == 0x802f2d7c) log_function("FUNCTION: AiDmaCallbackFunc__Q44nw4r3snd6detail9AxManagerFv");
if (state.pc == 0x802f2ea4) log_function("FUNCTION: __ct__Q44nw4r3snd6detail7AxVoiceFv");
if (state.pc == 0x802f2f28) log_function("FUNCTION: Setup__Q44nw4r3snd6detail7AxVoiceFPCvQ34nw4r3snd12SampleFormati");
if (state.pc == 0x802f333c) log_function("FUNCTION: SetLoopFlag__Q44nw4r3snd6detail7AxVoiceFb");
if (state.pc == 0x802f37a4) log_function("FUNCTION: IsDataAddressCoverd__Q44nw4r3snd6detail7AxVoiceCFPCvPCv");
if (state.pc == 0x802f39f0) log_function("FUNCTION: VoiceCallback__Q44nw4r3snd6detail7AxVoiceFPv");
if (state.pc == 0x802f3b14) log_function("FUNCTION: SetPriority__Q44nw4r3snd6detail7AxVoiceFUl");
if (state.pc == 0x802f3be8) log_function("FUNCTION: ResetDelta__Q44nw4r3snd6detail7AxVoiceFv");
if (state.pc == 0x802f40ec) log_function("FUNCTION: SetSrcType__Q44nw4r3snd6detail7AxVoiceFQ54nw4r3snd6detail7AxVoice7SrcTypef");
if (state.pc == 0x802f49e0) log_function("FUNCTION: SetRmtMix__Q44nw4r3snd6detail7AxVoiceFRCQ54nw4r3snd6detail7AxVoice14RemoteMixParam");
if (state.pc == 0x802f4c10) log_function("FUNCTION: SetVe__Q44nw4r3snd6detail7AxVoiceFff");
if (state.pc == 0x802f4cec) log_function("FUNCTION: SetLpf__Q44nw4r3snd6detail7AxVoiceFUs");
if (state.pc == 0x802f4e7c) log_function("FUNCTION: SetRemoteFilter__Q44nw4r3snd6detail7AxVoiceFUc");
if (state.pc == 0x802f52ec) log_function("FUNCTION: Set__Q44nw4r3snd6detail17AxVoiceParamBlockFP6_AXVPB");
if (state.pc == 0x802f5318) log_function("FUNCTION: SetVoiceMix__Q44nw4r3snd6detail17AxVoiceParamBlockFRC8_AXPBMIXb");
if (state.pc == 0x802f5590) log_function("FUNCTION: SetVoiceSrcType__Q44nw4r3snd6detail17AxVoiceParamBlockFUl");
if (state.pc == 0x802f5670) log_function("FUNCTION: SetVoiceRmtMix__Q44nw4r3snd6detail17AxVoiceParamBlockFRC11_AXPBRMTMIX");
if (state.pc == 0x802f585c) log_function("FUNCTION: SetVoiceRmtIIRCoefs__Q44nw4r3snd6detail17AxVoiceParamBlockFUse");
if (state.pc == 0x802f5a84) log_function("FUNCTION: __dt__Q44nw4r3snd6detail14AxVoiceManagerFv");
if (state.pc == 0x802f5b30) log_function("FUNCTION: Setup__Q44nw4r3snd6detail14AxVoiceManagerFPvUl");
if (state.pc == 0x802f5cec) log_function("FUNCTION: FreeAxVoice__Q44nw4r3snd6detail14AxVoiceManagerFPQ44nw4r3snd6detail7AxVoice");
if (state.pc == 0x802f5db8) log_function("FUNCTION: ReserveForFreeAxVoice__Q44nw4r3snd6detail14AxVoiceManagerFPQ44nw4r3snd6detail7AxVoice");
if (state.pc == 0x802f658c) log_function("FUNCTION: GetReferenceToSubRegion__Q44nw4r3snd6detail14BankFileReaderCFPCQ54nw4r3snd6detail4Util128DataRef<v,Q54nw4r3snd6detail8BankFile9InstParam,Q54nw4r3snd6detail8BankFile10RangeTable,Q54nw4r3snd6detail8BankFile10IndexTable>i");
if (state.pc == 0x802f682c) log_function("FUNCTION: SetFxSend__Q44nw4r3snd6detail11BasicPlayerFQ34nw4r3snd6AuxBusf");
if (state.pc == 0x802f6834) log_function("FUNCTION: SetCursorZ__Q36nw4hbm2ut10CharWriterFf");
if (state.pc == 0x802f683c) log_function("FUNCTION: GetFxSend__Q44nw4r3snd6detail11BasicPlayerCFQ34nw4r3snd6AuxBus");
if (state.pc == 0x802f7870) log_function("FUNCTION: SetModSpeed__Q44nw4r3snd6detail8SeqTrackFf");
if (state.pc == 0x802f79b8) log_function("FUNCTION: IsAttachedGeneralHandle__Q44nw4r3snd6detail10BasicSoundFv");
if (state.pc == 0x802f79cc) log_function("FUNCTION: IsAttachedTempGeneralHandle__Q44nw4r3snd6detail10BasicSoundFv");
if (state.pc == 0x802f8fdc) log_function("FUNCTION: __dt__Q34nw4r3snd15DvdSoundArchiveFv");
if (state.pc == 0x802f933c) log_function("FUNCTION: detail_GetRequiredStreamBufferSize__Q34nw4r3snd15DvdSoundArchiveCFv");
if (state.pc == 0x802f9344) log_function("FUNCTION: LoadHeader__Q34nw4r3snd15DvdSoundArchiveFPvUl");
if (state.pc == 0x802f93cc) log_function("FUNCTION: LoadLabelStringData__Q34nw4r3snd15DvdSoundArchiveFPvUl");
if (state.pc == 0x802f9454) log_function("FUNCTION: Read__Q44nw4r3snd15DvdSoundArchive13DvdFileStreamFPvUl");
if (state.pc == 0x802f9480) log_function("FUNCTION: Seek__Q44nw4r3snd15DvdSoundArchive13DvdFileStreamFlUl");
if (state.pc == 0x802f9510) log_function("FUNCTION: Tell__Q44nw4r3snd15DvdSoundArchive13DvdFileStreamCFv");
if (state.pc == 0x802f9520) log_function("FUNCTION: RoundUp<Ul>__Q34nw4r2ut33@unnamed@snd_McsSoundArchive_cpp@FUlUi_Ul");
if (state.pc == 0x802f9604) log_function("FUNCTION: Reset__Q44nw4r3snd6detail12EnvGeneratorFf");
if (state.pc == 0x802f961c) log_function("FUNCTION: GetValue__Q44nw4r3snd6detail12EnvGeneratorCFv");
if (state.pc == 0x802f976c) log_function("FUNCTION: SetAttack__Q44nw4r3snd6detail12EnvGeneratorFi");
if (state.pc == 0x802f9784) log_function("FUNCTION: SetDecay__Q44nw4r3snd6detail12EnvGeneratorFi");
if (state.pc == 0x802f982c) log_function("FUNCTION: SetRelease__Q44nw4r3snd6detail12EnvGeneratorFi");
if (state.pc == 0x802f99ac) log_function("FUNCTION: __ct__Q44nw4r3snd6detail9FrameHeapFv");
if (state.pc == 0x802f99d0) log_function("FUNCTION: __dt__Q44nw4r3snd6detail9FrameHeapFv");
if (state.pc == 0x802f9ae4) log_function("FUNCTION: Create__Q44nw4r3snd6detail9FrameHeapFPvUl");
if (state.pc == 0x802f9c80) log_function("FUNCTION: Destroy__Q44nw4r3snd6detail9FrameHeapFv");
if (state.pc == 0x802f9d70) log_function("FUNCTION: Clear__Q44nw4r3snd6detail9FrameHeapFv");
if (state.pc == 0x802f9e9c) log_function("FUNCTION: Alloc__Q44nw4r3snd6detail9FrameHeapFUlPFPvUlPv_vPv");
if (state.pc == 0x802f9f40) log_function("FUNCTION: GetFreeSize__Q44nw4r3snd6detail9FrameHeapCFv");
if (state.pc == 0x802fa4ac) log_function("FUNCTION: AllocImpl__Q44nw4r3snd6detail8PoolImplFv");
if (state.pc == 0x802fa574) log_function("FUNCTION: Reset__Q44nw4r3snd6detail3LfoFv");
if (state.pc == 0x802fa588) log_function("FUNCTION: Update__Q44nw4r3snd6detail3LfoFi");
if (state.pc == 0x802fa624) log_function("FUNCTION: GetValue__Q44nw4r3snd6detail3LfoCFv");
if (state.pc == 0x802fa7e4) log_function("FUNCTION: Setup__Q34nw4r3snd18MemorySoundArchiveFPCv");
if (state.pc == 0x802fa85c) log_function("FUNCTION: detail_GetFileAddress__Q34nw4r3snd18MemorySoundArchiveCFUl");
if (state.pc == 0x802fa90c) log_function("FUNCTION: detail_GetWaveDataFileAddress__Q34nw4r3snd18MemorySoundArchiveCFUl");
if (state.pc == 0x802fa9bc) log_function("FUNCTION: OpenStream__Q34nw4r3snd18MemorySoundArchiveCFPviUlUl");
if (state.pc == 0x802faa2c) log_function("FUNCTION: Close__Q44nw4r3snd18MemorySoundArchive16MemoryFileStreamFv");
if (state.pc == 0x802faa40) log_function("FUNCTION: Read__Q44nw4r3snd18MemorySoundArchive16MemoryFileStreamFPvUl");
if (state.pc == 0x802faa98) log_function("FUNCTION: Seek__Q44nw4r3snd18MemorySoundArchive16MemoryFileStreamFlUl");
if (state.pc == 0x802fb908) log_function("FUNCTION: NoteOnCommandProc__Q44nw4r3snd6detail9MmlParserCFPQ44nw4r3snd6detail11MmlSeqTrackiilb");
if (state.pc == 0x802fc684) log_function("FUNCTION: GetRemoteSpeaker__Q44nw4r3snd6detail20RemoteSpeakerManagerFi");
if (state.pc == 0x802fc694) log_function("FUNCTION: Setup__Q44nw4r3snd6detail20RemoteSpeakerManagerFv");
if (state.pc == 0x802fc828) log_function("FUNCTION: __ct__Q44nw4r3snd6detail13SeqFileReaderFPCv");
if (state.pc == 0x802fc894) log_function("FUNCTION: GetBaseAddress__Q44nw4r3snd6detail13SeqFileReaderCFv");
if (state.pc == 0x802fe254) log_function("FUNCTION: SetSeqData__Q44nw4r3snd6detail8SeqTrackFPCvl");
if (state.pc == 0x802ff1d0) log_function("FUNCTION: Shutdown__Q34nw4r3snd12SoundArchiveFv");
if (state.pc == 0x802ff1f8) log_function("FUNCTION: ConvertLabelStringToSoundId__Q34nw4r3snd12SoundArchiveCFPCc");
if (state.pc == 0x802ff208) log_function("FUNCTION: ConvertLabelStringToGroupId__Q34nw4r3snd12SoundArchiveCFPCc");
if (state.pc == 0x802ff4a4) log_function("FUNCTION: detail_OpenGroupStream__Q34nw4r3snd12SoundArchiveCFUlPvi");
if (state.pc == 0x802ff5bc) log_function("FUNCTION: detail_OpenGroupWaveDataStream__Q34nw4r3snd12SoundArchiveCFUlPvi");
if (state.pc == 0x802ff750) log_function("FUNCTION: __ct__Q44nw4r3snd6detail22SoundArchiveFileReaderFv");
if (state.pc == 0x802ff824) log_function("FUNCTION: SetStringChunk__Q44nw4r3snd6detail22SoundArchiveFileReaderFPCvUl");
if (state.pc == 0x802ff8cc) log_function("FUNCTION: SetInfoChunk__Q44nw4r3snd6detail22SoundArchiveFileReaderFPCvUl");
if (state.pc == 0x802ffbf8) log_function("FUNCTION: ReadBankInfo__Q44nw4r3snd6detail22SoundArchiveFileReaderCFUlPQ44nw4r3snd12SoundArchive8BankInfo");
if (state.pc == 0x802ffca4) log_function("FUNCTION: ReadPlayerInfo__Q44nw4r3snd6detail22SoundArchiveFileReaderCFUlPQ44nw4r3snd12SoundArchive10PlayerInfo");
if (state.pc == 0x802ffd5c) log_function("FUNCTION: ReadGroupInfo__Q44nw4r3snd6detail22SoundArchiveFileReaderCFUlPQ44nw4r3snd12SoundArchive9GroupInfo");
if (state.pc == 0x802ffe6c) log_function("FUNCTION: ReadGroupItemInfo__Q44nw4r3snd6detail22SoundArchiveFileReaderCFUlUlPQ44nw4r3snd12SoundArchive13GroupItemInfo");
if (state.pc == 0x802fffa4) log_function("FUNCTION: ReadSoundArchivePlayerInfo__Q44nw4r3snd6detail22SoundArchiveFileReaderCFPQ44nw4r3snd12SoundArchive22SoundArchivePlayerInfo");
if (state.pc == 0x80300028) log_function("FUNCTION: GetPlayerCount__Q44nw4r3snd6detail22SoundArchiveFileReaderCFv");
if (state.pc == 0x80300068) log_function("FUNCTION: GetGroupCount__Q44nw4r3snd6detail22SoundArchiveFileReaderCFv");
if (state.pc == 0x803000ac) log_function("FUNCTION: GetSoundUserParam__Q44nw4r3snd6detail22SoundArchiveFileReaderCFUl");
if (state.pc == 0x80300164) log_function("FUNCTION: ReadFileInfo__Q44nw4r3snd6detail22SoundArchiveFileReaderCFUlPQ44nw4r3snd12SoundArchive8FileInfo");
if (state.pc == 0x80300264) log_function("FUNCTION: ReadFilePos__Q44nw4r3snd6detail22SoundArchiveFileReaderCFUlUlPQ44nw4r3snd12SoundArchive7FilePos");
if (state.pc == 0x80300384) log_function("FUNCTION: ConvertLabelStringToId__Q44nw4r3snd6detail22SoundArchiveFileReaderCFPCQ54nw4r3snd6detail16SoundArchiveFile10StringTreePCc");
if (state.pc == 0x803004cc) log_function("FUNCTION: impl_GetSoundInfoOffset__Q44nw4r3snd6detail22SoundArchiveFileReaderCFUl");
if (state.pc == 0x8030063c) log_function("FUNCTION: LoadGroup__Q44nw4r3snd6detail18SoundArchiveLoaderFUlPQ34nw4r3snd22SoundMemoryAllocatablePPvUl");
if (state.pc == 0x80300c10) log_function("FUNCTION: ReadFile__Q44nw4r3snd6detail18SoundArchiveLoaderFUlPvll");
if (state.pc == 0x80300d9c) log_function("FUNCTION: LoadFile__Q44nw4r3snd6detail18SoundArchiveLoaderFUlPQ34nw4r3snd22SoundMemoryAllocatable");
if (state.pc == 0x80300e78) log_function("FUNCTION: Cancel__Q44nw4r3snd6detail18SoundArchiveLoaderFv");
if (state.pc == 0x80301584) log_function("FUNCTION: GetRequiredStrmBufferSize__Q34nw4r3snd18SoundArchivePlayerFPCQ34nw4r3snd12SoundArchive");
if (state.pc == 0x803027bc) log_function("FUNCTION: LoadGroup__Q34nw4r3snd18SoundArchivePlayerFUlPQ34nw4r3snd22SoundMemoryAllocatableUl");
if (state.pc == 0x80302924) log_function("FUNCTION: LoadGroup__Q34nw4r3snd18SoundArchivePlayerFPCcPQ34nw4r3snd22SoundMemoryAllocatableUl");
if (state.pc == 0x80302994) log_function("FUNCTION: InvalidateData__Q34nw4r3snd18SoundArchivePlayerFPCvPCv");
if (state.pc == 0x803029e8) log_function("FUNCTION: InvalidateWaveData__Q34nw4r3snd18SoundArchivePlayerFPCvPCv");
if (state.pc == 0x80303ad4) log_function("FUNCTION: DetachSound__Q34nw4r3snd11SoundHandleFv");
if (state.pc == 0x80303b6c) log_function("FUNCTION: __dt__Q34nw4r3snd9SoundHeapFv");
if (state.pc == 0x80303be4) log_function("FUNCTION: Alloc__Q34nw4r3snd9SoundHeapFUl");
if (state.pc == 0x80305064) log_function("FUNCTION: WaitForResetReady__Q34nw4r3snd11SoundSystemFv");
if (state.pc == 0x80305374) log_function("FUNCTION: SoundThreadFunc__Q44nw4r3snd6detail11SoundThreadFPv");
if (state.pc == 0x80305590) log_function("FUNCTION: Alloc__Q44nw4r3snd6detail14StrmBufferPoolFv");
if (state.pc == 0x80305950) log_function("FUNCTION: LoadFileHeader__Q44nw4r3snd6detail14StrmFileLoaderFPvUl");
if (state.pc == 0x803086e4) log_function("FUNCTION: __dt__Q44nw4r3snd6detail5VoiceFv");
if (state.pc == 0x80309a54) log_function("FUNCTION: IsCurrentAddressCoverd__Q44nw4r3snd6detail5VoiceCFiPCvPCv");
if (state.pc == 0x80309b34) log_function("FUNCTION: GetCurrentPlayingSample__Q44nw4r3snd6detail5VoiceCFv");
if (state.pc == 0x8030a164) log_function("FUNCTION: TransformDpl2Pan__Q44nw4r3snd6detail5VoiceFPfPfff");
if (state.pc == 0x8030ae30) log_function("FUNCTION: __dt__Q44nw4r3snd6detail12VoiceManagerFv");
if (state.pc == 0x8030b290) log_function("FUNCTION: Draw_ModifyScaleX__Q34nw4r2ef15ParticleManagerFPQ34nw4r2ef8Particlef");
if (state.pc == 0x8030b5dc) log_function("FUNCTION: CalcVolumeRatio__Q44nw4r3snd6detail4UtilFf");
if (state.pc == 0x8030b6fc) log_function("FUNCTION: CalcLpfFreq__Q44nw4r3snd6detail4UtilFf");
if (state.pc == 0x8030b768) log_function("FUNCTION: GetRemoteFilterCoefs__Q44nw4r3snd6detail4UtilFiPUsPUsPUsPUsPUs");
if (state.pc == 0x8030b7bc) log_function("FUNCTION: CalcRandom__Q44nw4r3snd6detail4UtilFv");
if (state.pc == 0x8030d7bc) log_function("FUNCTION: DecodeDspAdpcm__Q34nw4r3snd6detailFP10_AXPBADPCMUc");
if (state.pc == 0x8030e6c8) log_function("FUNCTION: setTriggerTarget__Q310homebutton3gui9ComponentFb");
if (state.pc == 0x803164c4) log_function("FUNCTION: getPane__Q310homebutton3gui13PaneComponentFv");
if (state.pc == 0x80316848) log_function("FUNCTION: do_calc__Q210homebutton18GroupAnmControllerFv");
if (state.pc == 0x803168f8) log_function("FUNCTION: init__Q210homebutton15FrameControllerFifff");
if (state.pc == 0x80316930) log_function("FUNCTION: initFrame__Q210homebutton15FrameControllerFv");
if (state.pc == 0x80316e68) log_function("FUNCTION: isPointed__Q310homebutton3gui9ComponentFi");
if (state.pc == 0x80316e78) log_function("FUNCTION: onEvent__Q310homebutton3gui7ManagerFUlUlPv");
if (state.pc == 0x80316ea0) log_function("FUNCTION: setPointed__Q310homebutton3gui9ComponentFib");
if (state.pc == 0x80316eb4) log_function("FUNCTION: __dt__Q310homebutton3gui7ManagerFv");
if (state.pc == 0x80316f70) log_function("FUNCTION: init__Q310homebutton3gui7ManagerFv");
if (state.pc == 0x80316fd8) log_function("FUNCTION: init__Q310homebutton3gui9ComponentFv");
if (state.pc == 0x80317004) log_function("FUNCTION: addComponent__Q310homebutton3gui7ManagerFPQ310homebutton3gui9Component");
if (state.pc == 0x803170d0) log_function("FUNCTION: getComponent__Q310homebutton3gui7ManagerFUl");
if (state.pc == 0x803172a0) log_function("FUNCTION: isTriggerTarger__Q310homebutton3gui9ComponentFv");
if (state.pc == 0x803172a8) log_function("FUNCTION: onTrig__Q310homebutton3gui9ComponentFUlR3Vec");
if (state.pc == 0x803172d8) log_function("FUNCTION: calc__Q310homebutton3gui7ManagerFv");
if (state.pc == 0x80317340) log_function("FUNCTION: draw__Q310homebutton3gui7ManagerFv");
if (state.pc == 0x803173a8) log_function("FUNCTION: setAllComponentTriggerTarget__Q310homebutton3gui7ManagerFb");
if (state.pc == 0x80317420) log_function("FUNCTION: __dt__Q310homebutton3gui11PaneManagerFv");
if (state.pc == 0x803178a0) log_function("FUNCTION: getPaneComponentByPane__Q310homebutton3gui11PaneManagerFPQ36nw4hbm3lyt4Pane");
if (state.pc == 0x80317e70) log_function("FUNCTION: VFipdm_close_disk");
if (state.pc == 0x80317e9c) log_function("FUNCTION: setEventHandler__Q310homebutton3gui7ManagerFPQ310homebutton3gui12EventHandler");
if (state.pc == 0x803180f4) log_function("FUNCTION: soundOnCallback__Q210homebutton10ControllerFP7OSAlarmP9OSContext");
if (state.pc == 0x8031847c) log_function("FUNCTION: clrKpadButton__Q210homebutton10ControllerFv");
if (state.pc == 0x803184b4) log_function("FUNCTION: setSpeakerVol__Q210homebutton10ControllerFf");
if (state.pc == 0x803185b0) log_function("FUNCTION: initSound__Q210homebutton10ControllerFv");
if (state.pc == 0x80318870) log_function("FUNCTION: stopMotor__Q210homebutton10ControllerFv");
if (state.pc == 0x80318e08) log_function("FUNCTION: DelaySpeakerOnCallback__Q210homebutton9RemoteSpkFP7OSAlarmP9OSContext");
if (state.pc == 0x80318efc) log_function("FUNCTION: DelaySpeakerPlayCallback__Q210homebutton9RemoteSpkFP7OSAlarmP9OSContext");
if (state.pc == 0x8031910c) log_function("FUNCTION: isPlaying__Q210homebutton9RemoteSpkCFl");
if (state.pc == 0x80319128) log_function("FUNCTION: isPlayingId__Q210homebutton9RemoteSpkCFli");
if (state.pc == 0x80319158) log_function("FUNCTION: isPlayReady__Q210homebutton9RemoteSpkCFl");
if (state.pc == 0x80c2d4c4) log_function("FUNCTION: HBMFreeMem__FPv");
if (state.pc == 0x80c6be0c) log_function("FUNCTION: gpiProfilesTableCompare");
if (state.pc == 0x8028906c) log_function("FUNCTION: DSPInterruptHandler");
if (state.pc == 0x8028901c) {
    log_function("DSP_PRINT");
            hle_os_report(cast(void*) &mem, &state);


}
if (state.pc == 0x802867f8) {
    log_function("DSP INIT RETURN");}
            }

// if (state.pc >= 0x80235ce0 && state.pc <= 0x80235f74) {
//     log_function("DSP INIT P4: %x", state.pc);
// }
// if (state.pc >= 0x80235600 && state.pc <= 0x80235ae4) {
//     log_function("stuck: %x", state.pc);
// }
// if (state.pc >= 0x8027bea4 && state.pc <= 0x8027c1c8) {
//     // log_function("stucker: %x", state.pc);
// }
// if (state.pc >= 0x801a71a4 && state.pc <= 0x801a7734) {
//     log_function("stuckerst: %x", state.pc); 
// }
// if (state.pc >= 0x801832e4 && state.pc <= 0x801833c4) {
//     log_function("stuckerst2: %x", state.pc); 
// }
// if (state.pc >= 0x8019b030 && state.pc <= 0x8019b194) {
//     log_function("stuckerst22: %x", state.pc); 
// }
// if (state.pc >= 0x801a6850 && state.pc <= 0x801a68b4) {
//     log_function("stuckerst222: %x", state.pc); 
// }
// if (state.pc >= 0x801a6508 && state.pc <= 0x801a684c) {
//     log_function("stuckerst2222: %x", state.pc); 
// }
// if (state.pc >= 0x8025b144 && state.pc <= 0x8025bea0) {
//     log_function("stuckerst22222: %x", state.pc); 
// }
// if (state.pc >= 0x8025c420 && state.pc <= 0x8025d810) {
//     log_function("stuckerst222222: %x", state.pc); 
// }
// if (state.pc >= 0x80256e04 && state.pc <= 0x802575b0) {
//     log_function("stuckerst2222222: %x", state.pc); 
//     // log_state(&state);
// }
// if (state.pc >= 0x802535dc && state.pc <= 0x80253634) {
//     // log_function("Current: %x", state.pc);
//     // log_state(&state);
// }
// if (scheduler.get_current_time_relative_to_cpu() > 0x00000001d7f6848) {
    // writefln("opcode: %x", mem.read_be_u32(state.pc));
    // log_state(&state);
// }

if (state.pc == 0x80288e10) { log_function("FUNCTION: DSPReadMailFromDSP() == %x", state.gprs[3]); }
// if (state.pc == 0x8027d224) { log_function("FUNCTION: DVD STATUS: %x", state.gprs[3]); } 
if ((state.gprs[1] & 0xFFFF0000) == 0xe21f0000) {
    error_jit("HLE: %x", state.pc);
}
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

            // check for decrementer interrupt
            auto old_dec = state.dec;
            state.dec -= delta;
            if (old_dec > 0 && state.dec <= 0) {
                raise_exception(ExceptionType.Decrementer);
            }
        
            handle_pending_interrupts();
            // } else if (old != state.msr.bit(15)) {
                // interrupt_controller.maybe_raise_processor_interface_interrupt();
            // }


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
        if (pending_interrupts > 0) {
            if (state.msr.bit(15)) {
                // log_function("Handling pending interrupt: %x", pending_interrupts);
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
}
 