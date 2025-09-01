// Originally based on: https://github.com/philpax/djitt
module gallinule.x86;

import std.bitmanip;
import std.traits;
import std.typecons;
import tern.algorithm;
import tern.state;

Reg!to cvt(ushort to, ushort from)(Reg!from r) {
    return Reg!to(r.index, (r.index & 4) && to == 8);
}

R64 cvt64(ushort T)(Reg!T r) {
    return cvt!(cast(ushort) 64, T)(r);
}

R32 cvt32(ushort T)(Reg!T r) {
    return cvt!(cast(ushort) 32, T)(r);
}

R16 cvt16(ushort T)(Reg!T r) {
    return cvt!(cast(ushort) 16, T)(r);
}

R8 cvt8(ushort T)(Reg!T r) {
    return cvt!(cast(ushort) 8, T)(r);
}

/* ====== ADDRESSING ====== */

private enum Mode
{
    Memory,
    MemoryOffset8,
    MemoryOffsetExt,
    Register
}

private union ModRM
{
public:
final:
    struct
    {
        mixin(bitfields!(
            ubyte, "src", 3,
            ubyte, "dst", 3,
            ubyte, "mod", 2
        ));
    }
    ubyte b;
    alias b this;
}

struct ZaydAppender {
    ubyte[0x40000] buffer;
    size_t pos = 0;

    void opOpAssign(string s : "~")(ubyte[] data) {
        foreach (ubyte b; data) {
            buffer[pos++] = b;
        }
    }


    void opOpAssign(string s : "~")(ubyte data) {
        buffer[pos++] = data;
    }

    void opBinary(string s : "~")(ubyte[] data) {
        foreach (ubyte b; data) {
            buffer[pos++] = b;
        }
    }

    void insert_at(size_t index, ubyte[] data) {
        // slide everything after index to the right
        foreach_reverse (i; index..pos) {
            buffer[i + data.length] = buffer[i];
        }
        
        foreach (ubyte b; data) {
            buffer[index++] = b;
        }

        pos += data.length;
    }

    void opBinary(string s : "~")(ubyte data) {
        buffer[pos++] = data;
    }

    ubyte opIndex(size_t index) {
        return buffer[index];
    }

    ubyte[] opSlice(size_t start, size_t end) {
        return buffer[start..end];
    }
    
    size_t opDollar() {
        return pos;
    }

    size_t length() {
        return pos;
    }

    void deallocate() {
        pos = 0;
    }

    void increment_end(size_t amount) {
        buffer[pos-1] += amount;
    }

    ubyte[] buffie() {
        return buffer[0..pos];
    }
}

private:
ubyte[] generateModRM(ubyte OP, SRC, DST)(SRC src, DST dst)
    if (isInstanceOf!(Address, SRC) && isInstanceOf!(Reg, DST))
{
    import std.stdio;
    // // // //("generateModRM(ubyte OP, SRC, DST)(SRC src, DST dst) %x %s", src.size, dst);
    if (src.size == 0)
        return generateModRM!OP(DST(src.register), dst, Mode.Memory)~0x25~(cast(ubyte*)&src.offset)[0..uint.sizeof];
    else
    {
        if (src.offset == 0)
            return generateModRM!OP(DST(src.register), dst, Mode.Memory);
        else
        {
            if (src.offset < byte.max)
                return generateModRM!OP(DST(src.register), dst, Mode.MemoryOffset8)~cast(ubyte)src.offset;
            else
                return generateModRM!OP(DST(src.register), dst, Mode.MemoryOffsetExt)~(cast(ubyte*)&src.offset)[0..uint.sizeof];
        }
    }
}

ubyte[] generateModRM(ubyte OP, SRC, DST)(SRC src, DST dst, Mode mod = Mode.Register)
    if (isInstanceOf!(Reg, SRC) && isInstanceOf!(Reg, DST))
{
    ModRM generateModRM;
    generateModRM.src = (src.index % 8);

    import std.stdio;
    //("dst: %x | %x", dst.index, OP);
    
    generateModRM.dst = (dst.index % 8) | OP;
    generateModRM.mod = cast(ubyte)mod;
    import std.stdio;
    //("generateModRM(ubyte OP, SRC, DST)(SRC src, DST dst, Mode mod = Mode.Register) %x %x %x", generateModRM.b, src.index, dst.index);
    return [generateModRM];
}

ubyte[] generateModRM(ubyte OP, SRC, DST)(SRC src, DST dst)
    if (isInstanceOf!(Address, SRC) && isInstanceOf!(Address, DST))
{
    return generateModRM!OP(Reg!(TemplateArgsOf!(DST))(dst.register), Reg!(TemplateArgsOf!(SRC))(src.register));
}

ubyte[] generateModRM(ubyte OP, SRC, DST)(SRC src, DST dst)
    if (isInstanceOf!(Reg, SRC) && isInstanceOf!(Address, DST))
{
    return generateModRM!OP(dst, src);
}

/// This is simply used for constraining T to be an address or register of the given size(s).
enum valid(T, short SIZE) = is(T == Reg!SIZE) || is(T == Address!SIZE);
enum valid(T, short RS, short AS) = is(T == Reg!RS) || is(T == Address!AS);

enum M = 0;
// Used for generating instructions with directly encoded registers.
enum NRM = 1;
// Used for generating instructions without REX prefixes.
enum NP = 2;
enum VEX = 3;
// Used for generating integer VEX instructions.
enum VEXI = 4;
enum EVEX = 5;
enum MVEX = 6;
// Exactly the same as NP except flips dst and src.
enum SSE = 7;

// map_select
enum XOP = 0;
enum DEFAULT = 1;
enum F38 = 2;
enum F3A = 3;
enum MSR = 7;

/**
    alias CR = Reg!(-1);
    alias DR = Reg!(-2);
    alias ST = Reg!(-3);
    alias R8 = Reg!8;
    alias R16 = Reg!16;
    alias R32 = Reg!32;
    alias R64 = Reg!64;
    alias MMX = Reg!64;
    alias XMM = Reg!128;
    alias YMM = Reg!256;
    alias ZMM = Reg!512;

    Addresses: Address!(SIZE)

    If the instruction is an integer instruction: use VEXI, otherwise use VEX (like emit!(MODRM_OR, KIND)),
    Emits are in the format emit(ubyte OP, ubyte SELECTOR = M, ubyte SIZE = 128, ubyte MAP = DEFAULT, ubyte PREFIX = 0)
    Map selection is specified by the part of the VEX prefix in docs after the width, ie:
        VEX.256.0F
            SIZE = 256
            MAP = 0F = DEFAULT
            PREFIX = 0
        VEX.128.0F3A.66
            SIZE = 128
            MAP = F3A
            PREFIX = 66
*/

/* ====== FRONT-END ====== */

public struct Reg(short SIZE)
{
public:
final:
    ubyte index;
    bool extended;
}

public struct Address(short SIZE)
{
public:
final:
    short size;
    ubyte register;
    uint offset;
    ubyte segment = ds;

    this(T)(T register, ubyte segment, uint offset = 0)
        if (isInstanceOf!(Reg, T))
    {
        this.size = TemplateArgsOf!(T)[0];
        this.register = register.index;
        this.offset = offset;
        this.segment = segment;
    }

    this(T)(T register, uint offset = 0)
        if (isInstanceOf!(Reg, T))
    {
        this.size = TemplateArgsOf!(T)[0];
        this.register = register.index;
        import std.stdio;
        // // // //("Address(T)(T register, uint offset = 0) %x %x %s", this.size, this.offset, register);
        this.offset = offset;
    }

    this(uint offset, ubyte segment = ds)
    {
        // TODO: Why? Is this even correct??
        this.register = 4;
        this.offset = offset;
        this.segment = segment;
    }
}

public enum CRID
{
    VME,
    PVI,
    TSD,
    DE,
    PSE,
    PAE,
    MCE,
    PGE,
    PCE,
    OSFXSR,
    OSXMMEXCPT,
    UMIP,
    // RESERVED
    VMXE = 13,
    SMXE,
    // RESERVED
    FSGSBASE = 16,
    PCIDE,
    OSXSAVE,
    // RESERVED
    SMEP = 20,
    SMAP,
    PKE,
    CET,
    PKS,
    UINTR
}

public enum CPUID7_EBX
{
    FSGSBASE,
    TSC_ADJUST,
    SGX,
    // LZCNT and TZCNT
    BMI1, 
    // XACQUIRE, XRELEASE, XTEST
    HLE,
    AVX2,
    FPDP,
    SMEP,
    BMI2,
    ERMS,
    // INVPCID
    INVPCID, 
    // XBEGIN, XABORT, XEND and XTEST
    RTM, 
    PQM,
    FPCSDS,
    // BND*/BOUND
    MPX, 
    PQE,
    AVX512F,
    AVX512DQ,
    // RDSEED
    RDSEED,
    // ADCX and ADOX
    ADX, 
    // CLAC and STAC
    SMAP, 
    AVX512IFMA,
    PCOMMIT, 
    // CLFLUSHOPT
    CLFLUSHOPT, 
    // CLWB
    CLWB,
    // PTWRITE 
    PT, 
    AVX512PF,
    AVX512ER,
    AVX512CD,
    SHA,
    AVX512BW,
    AVX512VL
}

public enum CPUID7_ECX
{
    PREFETCHWT1,
    AVX512VBMI,
    UMIP,
    PKU,
    OSPKE,
    AVX512VBMI2 = 6,
    // INCSSP, RDSSP, SAVESSP, RSTORSSP, SETSSBSY, CLRSSBSY, WRSS, WRUSS, ENDBR64, and ENDBR64
    CET,
    GFNI,
    VAES,
    VPCL,
    AVX512VNNI,
    AVX512BITALG,
    TME,
    // VPOPCNT{D,Q}
    AVX512VP,
    VA57 = 16,
    RDPID = 22,
    SGX_LC = 30
}

public enum CPUID7_EDX
{
    AVX512QVNNIW = 2,
    AVX512QFMA = 3,
    PCONFIG = 18,
    IBRS_IBPB = 26,
    STIBP = 27
}

public enum CPUID1_ECX
{
    // FISTTP
    SSE3,
    // PCLMULQDQ
    PCLMUL,
    DTES64,
    // MONITOR/MWAIT
    MON,
    DSCPL,
    // VM*
    VMX,
    SMX,
    EST,
    TM2,
    SSSE3,
    CID,
    SDBG,
    FMA,
    // CMPXCHG16B
    CX16,
    XTPR,
    PDCM,
    PCID,
    DCA,
    SSE4_1,
    SSE4_2,
    X2APIC,
    // MOVBE
    MOVBE,
    // POPCNT
    POPCNT,
    TSCD,
    // AES*
    AES,
    // XGETBV, XSETBV, XSAVEOPT, XSAVE, and XRSTOR
    XSAVE,
    OSXSAVE,
    AVX,
    // VCVTPH2PS and VCVTPS2PH
    F16C,
    // RDRAND
    RDRAND,
    HV
}

public enum CPUID1_EDX
{
    FPU,
    VME,
    DE,
    PSE,
    // RDTSC
    TSC,
    // RDMSR/WRMSR
    MSR,
    PAE,
    // CMPXCHG8B
    CX8,
    APIC,
    // SYSENTER/SYSEXIT
    SEP,
    MTRR,
    PGE,
    MCA,
    // CMOVcc
    CMOV,
    PAT,
    PSE36,
    PSN,
    // CLFLUSH
    CLFL,
    DS,
    ACPI,
    MMX,
    // FXSAVE/FXRSTOR
    FXSR,
    NP,
    SSE2,
    SS,
    HTT,
    TM,
    IA64,
    PBE
}

public:
alias CR = Reg!(-1);
alias DR = Reg!(-2);
alias ST = Reg!(-3);
alias R8 = Reg!8;
alias R16 = Reg!16;
alias R32 = Reg!32;
alias R64 = Reg!64;
alias MMX = Reg!64;
alias XMM = Reg!128;
alias YMM = Reg!256;
alias ZMM = Reg!512;

enum cr0 = CR(0);
enum cr2 = CR(2);
enum cr3 = CR(3);
enum cr4 = CR(4);

enum dr0 = DR(0);
enum dr1 = DR(1);
enum dr2 = DR(2);
enum dr3 = DR(3);
enum dr6 = DR(6);
enum dr7 = DR(7);

// ST registers aren't real registers, the FPU uses a stack
enum st0 = ST(0);
enum st1 = ST(1);
enum st2 = ST(2);
enum st3 = ST(3);
enum st4 = ST(4);
enum st5 = ST(5);
enum st6 = ST(6);
enum st7 = ST(7);

enum al = Reg!8(0);
enum cl = Reg!8(1);
enum dl = Reg!8(2);
enum bl = Reg!8(3);
enum ah = Reg!8(4);
enum ch = Reg!8(5);
enum dh = Reg!8(6);
enum bh = Reg!8(7);
enum spl = Reg!8(4, true);
enum bpl = Reg!8(5, true);
enum sil = Reg!8(6, true);
enum dil = Reg!8(7, true);
enum r8b = Reg!8(8);
enum r9b = Reg!8(9);
enum r10b = Reg!8(10);
enum r11b = Reg!8(11);
enum r12b = Reg!8(12);
enum r13b = Reg!8(13);
enum r14b = Reg!8(14);
enum r15b = Reg!8(15);

enum ax = Reg!16(0);
enum cx = Reg!16(1);
enum dx = Reg!16(2);
enum bx = Reg!16(3);
enum sp = Reg!16(4);
enum bp = Reg!16(5);
enum si = Reg!16(6);
enum di = Reg!16(7);
enum r8w = Reg!16(8);
enum r9w = Reg!16(9);
enum r10w = Reg!16(10);
enum r11w = Reg!16(11);
enum r12w = Reg!16(12);
enum r13w = Reg!16(13);
enum r14w = Reg!16(14);
enum r15w = Reg!16(15);

enum eax = Reg!32(0);
enum ecx = Reg!32(1);
enum edx = Reg!32(2);
enum ebx = Reg!32(3);
enum esp = Reg!32(4);
enum ebp = Reg!32(5);
enum esi = Reg!32(6);
enum edi = Reg!32(7);
enum r8d = Reg!32(8);
enum r9d = Reg!32(9);
enum r10d = Reg!32(10);
enum r11d = Reg!32(11);
enum r12d = Reg!32(12);
enum r13d = Reg!32(13);
enum r14d = Reg!32(14);
enum r15d = Reg!32(15);

enum rax = Reg!64(0);
enum rcx = Reg!64(1);
enum rdx = Reg!64(2);
enum rbx = Reg!64(3);
enum rsp = Reg!64(4);
enum rbp = Reg!64(5);
enum rsi = Reg!64(6);
enum rdi = Reg!64(7);
enum r8 = Reg!64(8);
enum r9 = Reg!64(9);
enum r10 = Reg!64(10);
enum r11 = Reg!64(11);
enum r12 = Reg!64(12);
enum r13 = Reg!64(13);
enum r14 = Reg!64(14);
enum r15 = Reg!64(15);

// TODO: This lets you do evil by using Reg!64 MMX as Reg!64 R64
enum mm0 = Reg!64(0);
enum mm1 = Reg!64(1);
enum mm2 = Reg!64(2);
enum mm3 = Reg!64(3);
enum mm4 = Reg!64(4);
enum mm5 = Reg!64(5);
enum mm6 = Reg!64(6);
enum mm7 = Reg!64(7);

enum xmm0 = Reg!128(0);
enum xmm1 = Reg!128(1);
enum xmm2 = Reg!128(2);
enum xmm3 = Reg!128(3);
enum xmm4 = Reg!128(4);
enum xmm5 = Reg!128(5);
enum xmm6 = Reg!128(6);
enum xmm7 = Reg!128(7);
enum xmm8 = Reg!128(8);
enum xmm9 = Reg!128(9);
enum xmm10 = Reg!128(10);
enum xmm11 = Reg!128(11);
enum xmm12 = Reg!128(12);
enum xmm13 = Reg!128(13);
enum xmm14 = Reg!128(14);
enum xmm15 = Reg!128(15);

enum ymm0 = Reg!256(0);
enum ymm1 = Reg!256(1);
enum ymm2 = Reg!256(2);
enum ymm3 = Reg!256(3);
enum ymm4 = Reg!256(4);
enum ymm5 = Reg!256(5);
enum ymm6 = Reg!256(6);
enum ymm7 = Reg!256(7);
enum ymm8 = Reg!256(8);
enum ymm9 = Reg!256(9);
enum ymm10 = Reg!256(10);
enum ymm11 = Reg!256(11);
enum ymm12 = Reg!256(12);
enum ymm13 = Reg!256(13);
enum ymm14 = Reg!256(14);
enum ymm15 = Reg!256(15);

enum zmm0 = Reg!512(0);
enum zmm1 = Reg!512(1);
enum zmm2 = Reg!512(2);
enum zmm3 = Reg!512(3);
enum zmm4 = Reg!512(4);
enum zmm5 = Reg!512(5);
enum zmm6 = Reg!512(6);
enum zmm7 = Reg!512(7);
enum zmm8 = Reg!512(8);
enum zmm9 = Reg!512(9);
enum zmm10 = Reg!512(10);
enum zmm11 = Reg!512(11);
enum zmm12 = Reg!512(12);
enum zmm13 = Reg!512(13);
enum zmm14 = Reg!512(14);
enum zmm15 = Reg!512(15);

enum ubyte es = 0x26;
enum ubyte cs = 0x2e;
enum ubyte ss = 0x36;
enum ubyte ds = 0x3e;
enum ubyte fs = 0x64;
enum ubyte gs = 0x65;

// TODO: SIB
// TODO: Fix parameter names to make them more clear
public struct Block(bool X64)
{
package:
final:
    ptrdiff_t[string] labels;
    Tuple!(ptrdiff_t, string, string, bool)[] branches;

public:
    ZaydAppender buffer;
    void reset() {
        buffer.deallocate();
        labels.clear();
        branches = [];
    }

    template emit(ubyte OP, ubyte SELECTOR = M, ubyte SIZE = 128, ubyte MAP = DEFAULT, ubyte PREFIX = 0, bool cursed = false)
    {
        size_t emit(ARGS...)(ARGS args)
        {
            import std.stdio;

            auto bytes = this.buffer.buffie();
            int length = bytes.length > 0x400000 ? 0 : cast(int) bytes.length;

            //("%d / %d", length, bytes.length);
            // print 8 at a time
            for (int i = 0; i < length; i += 8)
            {
                //("%02x %02x %02x %02x %02x %02x %02x %02x", bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3], bytes[i + 4], bytes[i + 5], bytes[i + 6], bytes[i + 7]);
            }

            foreach (i, arg; args)
            {
                // // //("ARGUMENT %s : %s", typeof(arg).stringof, arg);
            }

            // ubyte[] buffer;
            bool prefixed;
            ptrdiff_t ct = 0;

            bool isRM1(size_t INDEX)()
            {
                static if (INDEX >= ARGS.length)
                    return false;
                else static if (INDEX + 1 >= ARGS.length)
                    return isInstanceOf!(Reg, ARGS[INDEX]) || isInstanceOf!(Address, ARGS[INDEX]);
                else
                {
                    return (isInstanceOf!(Reg, ARGS[INDEX]) || isInstanceOf!(Address, ARGS[INDEX])) &&
                        !isInstanceOf!(Reg, ARGS[INDEX + 1]) && !isInstanceOf!(Address, ARGS[INDEX + 1]);
                }
            }
            
            bool isRM2(size_t INDEX)()
            {
                static if (INDEX + 1 >= ARGS.length)
                    return false;
                else
                    return (isInstanceOf!(Reg, ARGS[INDEX]) || isInstanceOf!(Address, ARGS[INDEX])) && isRM1!(INDEX + 1);
            }
            
            bool isRM3(size_t INDEX)()
            {
                static if (INDEX + 2 >= ARGS.length)
                    return false;
                else
                    return (isInstanceOf!(Reg, ARGS[INDEX]) || isInstanceOf!(Address, ARGS[INDEX])) &&
                        (isInstanceOf!(Reg, ARGS[INDEX + 1]) || isInstanceOf!(Address, ARGS[INDEX + 1])) && isRM1!(INDEX + 2);
            }

            void generateOpSizeOverridePrefix(SRC, DST, STOR = int)(SRC src, DST dst, STOR stor = STOR.init)
            {

                import std.stdio;
                static if (is(ARGS[0] == int) && is(ARGS[1] == int)) {
                    if (is(DST == Reg!16) && !(args[0] == 0x0f && (args[1] == 0xb7 || args[1] == 0xbf || 
                    args[1] == 0xb6 || args[1] == 0xbe || args[1] == 0xb7 || args[1] == 0xb6)))
                        buffer ~= 0x66;
                } else {
                    if (is(DST == Reg!16))
                        buffer ~= 0x66;
                }
                
                import std.stdio;
                static if (isInstanceOf!(Address, SRC))
                {
                        // // // //("src.size %x", src.size);

                    if ((X64 && src.size != 64) || (!X64 && src.size != 32))
                        buffer ~= 0x67;//~buffer;
                }

                static if (isInstanceOf!(Address, DST))
                {
                        // // // //(".size %x", dst.size);
                    if ((X64 && dst.size != 64) || (!X64 && dst.size != 32))
                        buffer ~= 0x67;//~buffer;
                }

            }

            static if (SELECTOR == M || SELECTOR == NRM || SELECTOR == NP || SELECTOR == SSE)
            void generateREXPrefix(SRC, DST, STOR = int)(SRC src, DST dst, STOR stor = STOR.init)
            {
                prefixed = true;
                bool hasRex;
                bool w;
                bool r;
                bool x;
                bool b;

                import std.stdio;
                //("SRC: %s, DST: %s", src, dst);
                bool has_address =  isInstanceOf!(Address, SRC) && !isInstanceOf!(Address, DST);
                has_address |= cursed;
                
                //("has_address: %s", has_address);
                static if (isInstanceOf!(Reg, SRC))
                {
                    // // //("    Reg1: %s %d", src, src.index);
                    hasRex |= is(SRC == Reg!64) || (is(SRC == Reg!8) && src.extended) || src.index >= 8;
                    w |= is(SRC == Reg!64);
                    if (has_address)
                        b |= src.index >= 8;
                    else
                        r |= src.index >= 8;
                }
                else static if (isInstanceOf!(Address, SRC))
                {
                    // // //("    1Address: %s", src);
                    hasRex |= src.register >= 8;
                    w |= is(SRC == Address!64);
                    b |= src.register >= 8;
                }
                
                static if (isInstanceOf!(Reg, DST))
                {
                    // // //("  2  Reg: %s %d", dst, dst.index);
                    hasRex |= is(DST == Reg!64) || (is(DST == Reg!8) && dst.extended) || dst.index >= 8;
                    w |= is(DST == Reg!64);
                    if (has_address)
                        r |= dst.index >= 8;
                    else
                        b |= dst.index >= 8;
                }
                else static if (isInstanceOf!(Address, DST))
                {
                    // // //("2    Address: %s", dst);
                    hasRex |= dst.register >= 8;
                    w |= is(DST == Address!64);
                    b |= dst.register >= 8;
                }

                import std.stdio;
                // // //("r: %s, x: %s, b: %s w: %s", r, x, b, w);

                // static if (isInstanceOf!(Address, SRC))
                // {
                //     if (src.segment != ds)
                //         buffer = src.segment~buffer;
                // }
                // else static if (isInstanceOf!(Address, DST))
                // {
                //     if (dst.segment != ds)
                //         buffer = dst.segment~buffer;
                // }

                static if (SELECTOR != NP)
                if (hasRex)
                {
                    ubyte rex = 0b01000000;
                    if (w) rex |= (1 << 3);
                    if (r) rex |= (1 << 2);
                    if (x) rex |= (1 << 1);
                    if (b) rex |= (1 << 0);
                    
                    size_t pos = 0;
                    foreach (i; 0..buffer.length)
                    {
                        if (buffer[pos] == 0xf2)
                            pos++;
                        else if (buffer[pos] == 0xf3)
                            pos++;
                        else if (buffer[pos] == 0xf0)
                            pos++;
                        else if (buffer[pos] == 0x66)
                            pos++;
                        else if (buffer[pos] == 0x67)
                            pos++;
                    }

                        import std.stdio;
                        // // // //("rex %x %x", OP, rex);
                    // static if (cursed) {
                        // rex &= ~(1 << 3);
                        // if (rex != 0x40) {
                            // buffer = buffer[0..pos]~rex~buffer[pos..$];
                        // }
                    // } else {
                        // buffer.insert_at(pos, [rex]);
                        buffer ~= rex;//~buffer[pos..$];
                    // }

                }
            }

            static if (SELECTOR == VEX || SELECTOR == VEXI)
            void generateREXPrefix(SRC, DST, STOR = int)(SRC src, DST dst, STOR stor = STOR.init)
            {
                prefixed = true;
                bool r;
                bool x;
                bool b;
                immutable ubyte map_select = MAP;
                bool we = SELECTOR == VEX;
                ubyte vvvv = 0b1111;
                immutable bool l = SIZE != 128;
                immutable ubyte pp = (PREFIX == 0x66) ? 1 : ((PREFIX == 0xf3) ? 2 : ((PREFIX == 0xf2) ? 3 : 0));

                static if (isInstanceOf!(Reg, STOR))
                {
                    static if (isInstanceOf!(Reg, DST))
                        vvvv = cast(ubyte)~dst.index;
                    else static if (isInstanceOf!(Address, DST))
                        vvvv = cast(ubyte)~dst.register;

                    dst = DST(stor.index);
                }
                else static if (isInstanceOf!(Address, STOR))
                {
                    static if (isInstanceOf!(Reg, DST))
                        vvvv = cast(ubyte)~dst.index;
                    else static if (isInstanceOf!(Address, DST))
                        vvvv = cast(ubyte)~dst.register;
                        
                    dst = DST(stor.register);
                }

                bool has_address =  isInstanceOf!(Address, SRC) && !isInstanceOf!(Address, DST);
                has_address |= cursed;
                
                // //("has_address: %s", has_address);
                static if (isInstanceOf!(Reg, SRC))
                {
                    // // //("    Reg1: %s %d", src, src.index);
                    // hasRex |= is(SRC == Reg!64) || (is(SRC == Reg!8) && src.extended) || src.index >= 8;
                    // w |= is(SRC == Reg!64);
                    // if (has_address)
                        b |= src.index >= 8;
                    // else
                        // r |= src.index >= 8;
                }
                else static if (isInstanceOf!(Address, SRC))
                {
                    // // //("    1Address: %s", src);
                    // hasRex |= src.register >= 8;
                    // w |= is(SRC == Address!64);
                    b |= src.register >= 8;
                }
                
                static if (isInstanceOf!(Reg, DST))
                {
                    // // //("  2  Reg: %s %d", dst, dst.index);
                    // hasRex |= is(DST == Reg!64) || (is(DST == Reg!8) && dst.extended) || dst.index >= 8;
                    // w |= is(DST == Reg!64);
                    // if (has_address)
                        r |= dst.index >= 8;
                    // else
                        // b |= dst.index >= 8;
                }
                else static if (isInstanceOf!(Address, DST))
                {
                    // // //("2    Address: %s", dst);
                    // hasRex |= dst.register >= 8;
                    // w |= is(DST == Address!64);
                    b |= dst.register >= 8;
                }

                // static if (isInstanceOf!(Reg, SRC))
                // {
                //     static if (SELECTOR == VEXI)
                //         we = is(SRC == Reg!64);
                //     b = src.index >= 8;
                // }
                // else static if (isInstanceOf!(Address, SRC))
                // {
                //     static if (SELECTOR == VEXI)
                //         we = is(SRC == Address!64);
                //     b = src.register >= 8;
                // }
                
                // static if (isInstanceOf!(Reg, DST))
                // {
                //     static if (SELECTOR == VEXI)
                //         we = is(DST == Reg!64);
                //     r = dst.index >= 8;
                // }
                // else static if (isInstanceOf!(Address, DST))
                // {
                //     static if (SELECTOR == VEXI)
                //         we = is(DST == Address!64);
                //     x = dst.register >= 8;
                // }

                // static if (isInstanceOf!(Address, SRC))
                // {
                //     if (src.segment != ds)
                //         buffer = src.segment~buffer;
                // }
                // else static if (isInstanceOf!(Address, DST))
                // {
                //     if (dst.segment != ds)
                //         buffer = dst.segment~buffer;
                // }

                ubyte[] vex;
                if (map_select != 1 || r || x || b || MAP == XOP)
                {
                    static if (SELECTOR != VEXI)
                        we = false;

                    vex ~= MAP == XOP ? 0x8f : 0xc4;
                    vex ~= (cast(ubyte)(((r ? 0 : 1) << 7) | ((x ? 0 : 1) << 6) | ((b ? 0 : 1) << 5))) | (map_select & 0b00011111);
                }
                else
                    vex ~= 0xc5;
                vex ~= we << 7 | (vvvv & 0b00001111) << 3 | (l ? 1 : 0) << 2 | (pp & 0b00000011);
                buffer ~= vex;
                // buffer = vex~buffer;
                
                // import std.stdio;
                // static if (isInstanceOf!(Address, SRC))
                // {
                //     if ((X64 && src.size != 64) || (!X64 && src.size != 32)) {
                //         // // // //("src.size %x", src.size);
                //         buffer = 0x67~buffer;
                //     }
                // }

                // static if (isInstanceOf!(Address, DST))
                // {
                //     if ((X64 && dst.size != 64) || (!X64 && dst.size != 32)) {
                //         // // // //("asdfsrc.size %x", dst.size);
                //         buffer = 0x67~buffer;
                //     }
                // }
            }
                static if (args.length > 0) {
                    static if (is(typeof(args[0]) == int)) {
                        if (cast(ubyte)args[0] == 0x66 || cast(ubyte)args[0] == 0xf2 || cast(ubyte)args[0] == 0xf3) {
                            buffer ~= cast(ubyte)args[0];
                        }
                    }
                }

            // // //("ARGUMENTS: %d", args.length);
            foreach (i, arg; args)
            {
                // //("ballsaco and vaginetti %d %s\n", i, typeof(arg).stringof);
                if (ct-- > 0)
                    continue;

                static if (is(typeof(arg) == int)){}
                else static if (is(typeof(arg) == long)){}
                else static if (isScalarType!(typeof(arg))){}
                else static if (is(typeof(arg) == ubyte[])) {}
                else static if (SELECTOR == NRM && isInstanceOf!(Reg, typeof(arg)))
                {
                    generateOpSizeOverridePrefix(typeof(arg)(0), arg);
                }
                else static if (isRM1!i)
                {
                    auto dst = arg;
                    auto src = Reg!(TemplateArgsOf!(typeof(arg)))(0);
                    generateOpSizeOverridePrefix(src, dst);
                }
                else static if (isRM2!i)
                {
                    auto dst = arg;
                    auto src = args[i + 1];
                    generateOpSizeOverridePrefix(src, dst);
                    ct = 1;
                }
                else static if (isRM3!i)
                {
                    auto dst = args[i + 2];
                    auto src = arg;
                    generateOpSizeOverridePrefix(src, args[i + 1], dst);
                    ct = 2;
                }
                else
                    static assert(0, "May not emit a non-scalar, non-ubyte[] value of type '"~typeof(arg).stringof~"'!");
            }

            // // //("ARGUMENTS: %d", args.length);
            foreach (i, arg; args)
            {
                // //("ballsaco and vaginetti %d %s\n", i, typeof(arg).stringof);
                if (ct-- > 0)
                    continue;

                static if (is(typeof(arg) == int)){}
                else static if (is(typeof(arg) == long)){}
                else static if (isScalarType!(typeof(arg))){}
                else static if (is(typeof(arg) == ubyte[])) {}
                else static if (SELECTOR == NRM && isInstanceOf!(Reg, typeof(arg)))
                {
                    generateREXPrefix(typeof(arg)(0), arg);
                }
                else static if (isRM1!i)
                {
                    auto dst = arg;
                    auto src = Reg!(TemplateArgsOf!(typeof(arg)))(0);
                    generateREXPrefix(src, dst);
                }
                else static if (isRM2!i)
                {
                    auto dst = arg;
                    auto src = args[i + 1];
                    generateREXPrefix(src, dst);
                    ct = 1;
                }
                else static if (isRM3!i)
                {
                    auto dst = args[i + 2];
                    auto src = arg;
                    generateREXPrefix(src, args[i + 1], dst);
                    ct = 2;
                }
                else
                    static assert(0, "May not emit a non-scalar, non-ubyte[] value of type '"~typeof(arg).stringof~"'!");
            }


            foreach (i, arg; args)
            {
                if (ct-- > 0)
                    continue;
                static if (is(typeof(arg) == int)) {
                    if (!(i == 0 && (cast(ubyte)arg == 0x66 || cast(ubyte)arg == 0xf2 || cast(ubyte)arg == 0xf3))) {
                    buffer ~= cast(ubyte)arg;
                    } }
                else static if (is(typeof(arg) == long))
                    buffer ~= (cast(ubyte*)&arg)[0..uint.sizeof];
                else static if (isScalarType!(typeof(arg)))
                    buffer ~= (cast(ubyte*)&arg)[0..typeof(arg).sizeof];
                else static if (is(typeof(arg) == ubyte[]))
                    buffer ~= arg;
                else static if (SELECTOR == NRM && isInstanceOf!(Reg, typeof(arg)))
                {
                    // // //("shit1\n");
                    buffer.increment_end(arg.index % 8);
                }
                else static if (isRM1!i)
                {
                    auto dst = arg;
                    auto src = Reg!(TemplateArgsOf!(typeof(arg)))(0);
                    static if (SELECTOR == M || SELECTOR == NP || SELECTOR == NRM)
                        buffer ~= generateModRM!OP(dst, src);
                    else
                        buffer ~= generateModRM!OP(src, dst);
                }
                else static if (isRM2!i)
                {
                    auto dst = arg;
                    auto src = args[i + 1];
                    static if (SELECTOR == M || SELECTOR == NP || SELECTOR == NRM)
                        buffer ~= generateModRM!OP(dst, src);
                    else
                        buffer ~= generateModRM!OP(src, dst);
                    ct = 1;
                }
                else static if (isRM3!i)
                {
                    auto dst = args[i + 2];
                    auto src = arg;
                    buffer ~= generateModRM!OP(dst, src);
                    ct = 2;
                }
                else
                    static assert(0, "May not emit a non-scalar, non-ubyte[] value of type '"~typeof(arg).stringof~"'!");
            }

            if (!prefixed)
            {
                    // // //("shittest\n");
                static if (SELECTOR != M && SELECTOR != NP && SELECTOR != NP && SELECTOR != NRM)
                    generateOpSizeOverridePrefix(Reg!(typeof(args[0]).sizeof * 128)(0), Reg!(typeof(args[0]).sizeof * 128)(0));

                static if (SELECTOR == M || SELECTOR == NP || SELECTOR == NP || SELECTOR == NRM)
                foreach (i, arg; args)
                {
                    static if (!is(typeof(arg) == int))
                    {
                    // // //("shit1 %d\n", args.length - i - 1);
                        static if (args.length - i - 1 == 0)
                            generateOpSizeOverridePrefix(Reg!(typeof(arg).sizeof * 8)(0), Reg!(typeof(arg).sizeof * 8)(0));
                        else static if (args.length - i - 1 == 1)
                            generateOpSizeOverridePrefix(Reg!(typeof(arg).sizeof * 8)(0), Reg!(typeof(args[i + 1]).sizeof * 8)(0));
                        else static if (args.length - i - 1 == 2)
                            generateOpSizeOverridePrefix(Reg!(typeof(arg).sizeof * 8)(0), Reg!(typeof(args[i + 1]).sizeof * 8)(0), Reg!(typeof(args[i + 2]).sizeof * 8)(0));
                        break;
                    }
                }
            }

            if (!prefixed)
            {
                    // // //("shittest\n");
                static if (SELECTOR != M && SELECTOR != NP && SELECTOR != NP && SELECTOR != NRM)
                    generateREXPrefix(Reg!(typeof(args[0]).sizeof * 128)(0), Reg!(typeof(args[0]).sizeof * 128)(0));

                static if (SELECTOR == M || SELECTOR == NP || SELECTOR == NP || SELECTOR == NRM)
                foreach (i, arg; args)
                {
                    static if (!is(typeof(arg) == int))
                    {
                    // // //("shit1 %d\n", args.length - i - 1);
                        static if (args.length - i - 1 == 0)
                            generateREXPrefix(Reg!(typeof(arg).sizeof * 8)(0), Reg!(typeof(arg).sizeof * 8)(0));
                        else static if (args.length - i - 1 == 1)
                            generateREXPrefix(Reg!(typeof(arg).sizeof * 8)(0), Reg!(typeof(args[i + 1]).sizeof * 8)(0));
                        else static if (args.length - i - 1 == 2)
                            generateREXPrefix(Reg!(typeof(arg).sizeof * 8)(0), Reg!(typeof(args[i + 1]).sizeof * 8)(0), Reg!(typeof(args[i + 2]).sizeof * 8)(0));
                        break;
                    }
                }
            }

            // this.buffer ~= buffer;
            return buffer.length;
        }
    }

    ubyte[] finalize()
    {
        immutable static ubyte[][string] branchMap = [
            "jmp1": [0xeb],
            "jmp2": [0xe9],
            "jmp4": [0xe9],
            "ja1": [0x77],
            "jae1": [0x73],
            "jb1": [0x72],
            "jbe1": [0x76],
            "jc1": [0x72],
            "jecxz1": [0xE3],
            "jecxz1": [0xE3],
            "jrcxz1": [0xE3],
            "je1": [0x74],
            "jg1": [0x7F],
            "jge1": [0x7D],
            "jl1": [0x7C],
            "jle1": [0x7E],
            "jna1": [0x76],
            "jnae1": [0x72],
            "jnb1": [0x73],
            "jnbe1": [0x77],
            "jnc1": [0x73],
            "jne1": [0x75],
            "jng1": [0x7E],
            "jnge1": [0x7C],
            "jnl1": [0x7D],
            "jnle1": [0x7F],
            "jno1": [0x71],
            "jnp1": [0x7B],
            "jns1": [0x79],
            "jnz1": [0x75],
            "jo1": [0x70],
            "jp1": [0x7A],
            "jpe1": [0x7A],
            "jpo1": [0x7B],
            "js1": [0x78],
            "jz1": [0x74],
            "ja2": [0x0F, 0x87],
            "ja4": [0x0F, 0x87],
            "jae2": [0x0F, 0x83],
            "jae4": [0x0F, 0x83],
            "jb2": [0x0F, 0x82],
            "jb4": [0x0F, 0x82],
            "jbe2": [0x0F, 0x86],
            "jbe4": [0x0F, 0x86],
            "jc2": [0x0F, 0x82],
            "jc4": [0x0F, 0x82],
            "je2": [0x0F, 0x84],
            "je4": [0x0F, 0x84],
            "jz2": [0x0F, 0x84],
            "jz4": [0x0F, 0x84],
            "jg2": [0x0F, 0x8F],
            "jg4": [0x0F, 0x8F],
            "jge2": [0x0F, 0x8D],
            "jge4": [0x0F, 0x8D],
            "jl2": [0x0F, 0x8C],
            "jl4": [0x0F, 0x8C],
            "jle2": [0x0F, 0x8E],
            "jle4": [0x0F, 0x8E],
            "jna2": [0x0F, 0x86],
            "jna4": [0x0F, 0x86],
            "jnae2": [0x0F, 0x82],
            "jnae4": [0x0F, 0x82],
            "jnb2": [0x0F, 0x83],
            "jnb4": [0x0F, 0x83],
            "jnbe2": [0x0F, 0x87],
            "jnbe4": [0x0F, 0x87],
            "jnc2": [0x0F, 0x83],
            "jnc4": [0x0F, 0x83],
            "jne2": [0x0F, 0x85],
            "jne4": [0x0F, 0x85],
            "jng2": [0x0F, 0x8E],
            "jng4": [0x0F, 0x8E],
            "jnge2": [0x0F, 0x8C],
            "jnge4": [0x0F, 0x8C],
            "jnl2": [0x0F, 0x8D],
            "jnl4": [0x0F, 0x8D],
            "jnle2": [0x0F, 0x8F],
            "jnle4": [0x0F, 0x8F],
            "jno2": [0x0F, 0x81],
            "jno4": [0x0F, 0x81],
            "jnp2": [0x0F, 0x8B],
            "jnp4": [0x0F, 0x8B],
            "jns2": [0x0F, 0x89],
            "jns4": [0x0F, 0x89],
            "jnz2": [0x0F, 0x85],
            "jnz4": [0x0F, 0x85],
            "jo2": [0x0F, 0x80],
            "jo4": [0x0F, 0x80],
            "jp2": [0x0F, 0x8A],
            "jp4": [0x0F, 0x8A],
            "jpe2": [0x0F, 0x8A],
            "jpe4": [0x0F, 0x8A],
            "jpo2": [0x0F, 0x8B],
            "jpo4": [0x0F, 0x8B],
            "js2": [0x0F, 0x88],
            "js4": [0x0F, 0x88],
            "jz2": [0x0F, 0x84],
            "jz4": [0x0F, 0x84],
            "loop1": [0xe2],
            "loope1": [0xe1],
            "loopne1": [0xe0]
        ];

        size_t abs;
        size_t calculateBranch(T)(T branch)
        {
            size_t size;
            auto rel = labels[branch[1]] - branch[0] + abs;
            bool isRel8 = rel <= ubyte.max && rel >= ubyte.min;
            bool isRel16 = rel <= ushort.max && rel >= ushort.min;
import std.stdio;


            if (isRel8)
                size = branchMap[branch[2]~'1'].length + 1;
            else if (isRel16)
                size = branchMap[branch[2]~'2'].length + 2;
            else
                size = branchMap[branch[2]~'4'].length + 4;

            return size;
        }

        // foreach (ref i, branch; branches)
        // {
        //     import std.stdio;
        //     //("branch: %x %s %s %s\n", branch[0], branch[1], branch[2], branch[3]);
        //     // if (i + 1 < branches.length && branches[i + 1][3] && branches[i + 1][0] == branch[0])

        //     ubyte[] buffer;

        //     branch[0] += abs;
        //     auto rel = labels[branch[1]] - branch[0];
        //     bool isRel8 = rel <= byte.max && rel >= byte.min;
        //     bool isRel16 = rel <= short.max && rel >= short.min;

        //     buffer ~= branchMap[branch[2]~(isRel8 ? '1' : isRel16 ? '2' : '4')];

        //     if (isRel8)
        //         buffer ~= cast(ubyte)rel;
        //     else if (isRel16)
        //         buffer ~= (cast(ubyte*)&rel)[0..2];
        //     else
        //         buffer ~= (cast(ubyte*)&rel)[0..4];

        //     abs += buffer.length;
        //     //("rel %x - %x = %x\n", labels[branch[1]], branch[0], rel);
        //     this.buffer = this.buffer[0..branch[0]]~buffer~this.buffer[branch[0]..$];
        // }
            auto bytes = this.buffer.buffie();
            for (int i = 0; i < bytes.length - 8; i+= 8) {
                import std.stdio;
                //("%02x %02x %02x %02x %02x %02x %02x %02x", bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3], bytes[i + 4], bytes[i + 5], bytes[i + 6], bytes[i + 7]);
            }
        // reverse(branches);
        for (int i = cast(int) branches.length - 1; i >= 0; i--) {
            auto branch = branches[i];

            auto branch_address = labels[branch[1]];
            auto next_instruction_address = branch[0];
            import std.stdio;
            //("%s: rel = %x - %x = %x", branch[1], branch_address, next_instruction_address, branch_address - next_instruction_address);
            auto rel = branch_address - next_instruction_address;

            bool isRel8 = rel <= byte.max && rel >= byte.min;
            bool isRel16 = rel <= short.max && rel >= short.min;
            //("rel8: %x rel16: %x", isRel8, isRel16);

            ubyte[] jmp_buffer;
            jmp_buffer ~= branchMap[branch[2]~(isRel8 ? '1' : isRel16 ? '2' : '4')];
            // //("branch[2] %s", branch[2]);

            if (isRel8)
                jmp_buffer ~= cast(ubyte)rel;
            else if (isRel16)
                jmp_buffer ~= (cast(ubyte*)&rel)[0..4];
            else
                jmp_buffer ~= (cast(ubyte*)&rel)[0..4];

            //("Inserting %s at %x", jmp_buffer, branch[0]);
            this.buffer.insert_at(branch[0], jmp_buffer);
            // buffer = buffer[0..branch[0]]~jmp_buffer~buffer[branch[0]..$];
            // fixup all the remaining addresses
            foreach (ref label; labels) {
                if (label >= branch[0]) {
                    label += jmp_buffer.length;
                }
            }
        }

        branches = null;
        return this.buffer.buffie();
    }

    auto label(string name) => labels[name] = buffer.length;
    
    // These categories are intended to separate instructions based on their corresponding flag,
    // however, they do not accurately reflect this and are more whimsical than logical.

    /* ====== PSEUDO/CUSTOM ====== */

    auto cridvme() => mov(rax, cr4) + shr(rax, CRID.VME) + and(rax, 1);
    auto cridpvi() => mov(rax, cr4) + shr(rax, CRID.PVI) + and(rax, 1);
    auto cridtsd() => mov(rax, cr4) + shr(rax, CRID.TSD) + and(rax, 1);
    auto cridde() => mov(rax, cr4) + shr(rax, CRID.DE) + and(rax, 1);
    auto cridpse() => mov(rax, cr4) + shr(rax, CRID.PSE) + and(rax, 1);
    auto cridpae() => mov(rax, cr4) + shr(rax, CRID.PAE) + and(rax, 1);
    auto cridmce() => mov(rax, cr4) + shr(rax, CRID.MCE) + and(rax, 1);
    auto cridpge() => mov(rax, cr4) + shr(rax, CRID.PGE) + and(rax, 1);
    auto cridpce() => mov(rax, cr4) + shr(rax, CRID.PCE) + and(rax, 1);
    auto cridosfxsr() => mov(rax, cr4) + shr(rax, CRID.OSFXSR) + and(rax, 1);
    auto cridosxmmexcpt() => mov(rax, cr4) + shr(rax, CRID.OSXMMEXCPT) + and(rax, 1);
    auto cridumip() => mov(rax, cr4) + shr(rax, CRID.UMIP) + and(rax, 1);
    auto cridvmxe() => mov(rax, cr4) + shr(rax, CRID.VMXE) + and(rax, 1);
    auto cridsmxe() => mov(rax, cr4) + shr(rax, CRID.SMXE) + and(rax, 1);
    auto cridfsgsbase() => mov(rax, cr4) + shr(rax, CRID.FSGSBASE) + and(rax, 1);
    auto cridpcide() => mov(rax, cr4) + shr(rax, CRID.PCIDE) + and(rax, 1);
    auto cridosxsave() => mov(rax, cr4) + shr(rax, CRID.OSXSAVE) + and(rax, 1);
    auto cridsmep() => mov(rax, cr4) + shr(rax, CRID.SMEP) + and(rax, 1);
    auto cridsmap() => mov(rax, cr4) + shr(rax, CRID.SMAP) + and(rax, 1);
    auto cridpke() => mov(rax, cr4) + shr(rax, CRID.PKE) + and(rax, 1);
    auto cridcet() => mov(rax, cr4) + shr(rax, CRID.CET) + and(rax, 1);
    auto cridpks() => mov(rax, cr4) + shr(rax, CRID.PKS) + and(rax, 1);
    auto criduintr() => mov(rax, cr4) + shr(rax, CRID.UINTR) + and(rax, 1);

    auto idavx512vl() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX512VL) + and(ebx, 1);
    auto idavx512bw() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX512BW) + and(ebx, 1);
    auto idsha() => cpuid(7) + shr(ebx, CPUID7_EBX.SHA) + and(ebx, 1);
    auto idavx512cd() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX512CD) + and(ebx, 1);
    auto idavx512er() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX512ER) + and(ebx, 1);
    auto idavx512pf() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX512PF) + and(ebx, 1);
    auto idpt() => cpuid(7) + shr(ebx, CPUID7_EBX.PT) + and(ebx, 1);
    auto idclwb() => cpuid(7) + shr(ebx, CPUID7_EBX.CLWB) + and(ebx, 1);
    auto idclflushopt() => cpuid(7) + shr(ebx, CPUID7_EBX.CLFLUSHOPT) + and(ebx, 1);
    auto idpcommit() => cpuid(7) + shr(ebx, CPUID7_EBX.PCOMMIT) + and(ebx, 1);
    auto idavx512ifma() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX512IFMA) + and(ebx, 1);
    auto idsmap() => cpuid(7) + shr(ebx, CPUID7_EBX.SMAP) + and(ebx, 1);
    auto idadx() => cpuid(7) + shr(ebx, CPUID7_EBX.ADX) + and(ebx, 1);
    auto idrdseed() => cpuid(7) + shr(ebx, CPUID7_EBX.RDSEED) + and(ebx, 1);
    auto idavx512dq() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX512DQ) + and(ebx, 1);
    auto idavx512f() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX512F) + and(ebx, 1);
    auto idpqe() => cpuid(7) + shr(ebx, CPUID7_EBX.PQE) + and(ebx, 1);
    auto idrtm() => cpuid(7) + shr(ebx, CPUID7_EBX.RTM) + and(ebx, 1);
    auto idinvpcid() => cpuid(7) + shr(ebx, CPUID7_EBX.INVPCID) + and(ebx, 1);
    auto iderms() => cpuid(7) + shr(ebx, CPUID7_EBX.ERMS) + and(ebx, 1);
    auto idbmi2() => cpuid(7) + shr(ebx, CPUID7_EBX.BMI2) + and(ebx, 1);
    auto idsmep() => cpuid(7) + shr(ebx, CPUID7_EBX.SMEP) + and(ebx, 1);
    auto idfpdp() => cpuid(7) + shr(ebx, CPUID7_EBX.FPDP) + and(ebx, 1);
    auto idavx2() => cpuid(7) + shr(ebx, CPUID7_EBX.AVX2) + and(ebx, 1);
    auto idhle() => cpuid(7) + shr(ebx, CPUID7_EBX.HLE) + and(ebx, 1);
    auto idbmi1() => cpuid(7) + shr(ebx, CPUID7_EBX.BMI1) + and(ebx, 1);
    auto idsgx() => cpuid(7) + shr(ebx, CPUID7_EBX.SGX) + and(ebx, 1);
    auto idtscadj() => cpuid(7) + shr(ebx, CPUID7_EBX.TSC_ADJUST) + and(ebx, 1);
    auto idfsgsbase() => cpuid(7) + shr(ebx, CPUID7_EBX.FSGSBASE) + and(ebx, 1);

    auto idprefetchwt1() => cpuid(7) + shr(ecx, CPUID7_ECX.PREFETCHWT1) + and(ecx, 1);
    auto idavx512vbmi() => cpuid(7) + shr(ecx, CPUID7_ECX.AVX512VBMI) + and(ecx, 1);
    auto idumip() => cpuid(7) + shr(ecx, CPUID7_ECX.UMIP) + and(ecx, 1);
    auto idpku() => cpuid(7) + shr(ecx, CPUID7_ECX.PKU) + and(ecx, 1);
    auto idospke() => cpuid(7) + shr(ecx, CPUID7_ECX.OSPKE) + and(ecx, 1);
    auto idavx512vbmi2() => cpuid(7) + shr(ecx, CPUID7_ECX.AVX512VBMI2) + and(ecx, 1);
    auto idcet() => cpuid(7) + shr(ecx, CPUID7_ECX.CET) + and(ecx, 1);
    auto idgfni() => cpuid(7) + shr(ecx, CPUID7_ECX.GFNI) + and(ecx, 1);
    auto idvaes() => cpuid(7) + shr(ecx, CPUID7_ECX.VAES) + and(ecx, 1);
    auto idvpcl() => cpuid(7) + shr(ecx, CPUID7_ECX.VPCL) + and(ecx, 1);
    auto idavx512vnni() => cpuid(7) + shr(ecx, CPUID7_ECX.AVX512VNNI) + and(ecx, 1);
    auto idavx512bitalg() => cpuid(7) + shr(ecx, CPUID7_ECX.AVX512BITALG) + and(ecx, 1);
    auto idtme() => cpuid(7) + shr(ecx, CPUID7_ECX.TME) + and(ecx, 1);
    auto idavx512vp() => cpuid(7) + shr(ecx, CPUID7_ECX.AVX512VP) + and(ecx, 1);
    auto idva57() => cpuid(7) + shr(ecx, CPUID7_ECX.VA57) + and(ecx, 1);
    auto idrdpid() => cpuid(7) + shr(ecx, CPUID7_ECX.RDPID) + and(ecx, 1);
    auto idsgxlc() => cpuid(7) + shr(ecx, CPUID7_ECX.SGX_LC) + and(ecx, 1);

    auto idavx512qvnniw() => cpuid(7) + shr(edx, CPUID7_EDX.AVX512QVNNIW) + and(edx, 1);
    auto idavx512qfma() => cpuid(7) + shr(edx, CPUID7_EDX.AVX512QFMA) + and(edx, 1);
    auto idpconfig() => cpuid(7) + shr(edx, CPUID7_EDX.PCONFIG) + and(edx, 1);
    auto idibrsibpb() => cpuid(7) + shr(edx, CPUID7_EDX.IBRS_IBPB) + and(edx, 1);
    auto idstibp() => cpuid(7) + shr(edx, CPUID7_EDX.STIBP) + and(edx, 1);

    auto idsse3() => cpuid(1) + shr(ecx, CPUID1_ECX.SSE3) + and(ecx, 1);
    auto idpclmul() => cpuid(1) + shr(ecx, CPUID1_ECX.PCLMUL) + and(ecx, 1);
    auto iddtes64() => cpuid(1) + shr(ecx, CPUID1_ECX.DTES64) + and(ecx, 1);
    auto idmon() => cpuid(1) + shr(ecx, CPUID1_ECX.MON) + and(ecx, 1);
    auto iddscpl() => cpuid(1) + shr(ecx, CPUID1_ECX.DSCPL) + and(ecx, 1);
    auto idvmx() => cpuid(1) + shr(ecx, CPUID1_ECX.VMX) + and(ecx, 1);
    auto idsmx() => cpuid(1) + shr(ecx, CPUID1_ECX.SMX) + and(ecx, 1);
    auto idest() => cpuid(1) + shr(ecx, CPUID1_ECX.EST) + and(ecx, 1);
    auto idtm2() => cpuid(1) + shr(ecx, CPUID1_ECX.TM2) + and(ecx, 1);
    auto idssse3() => cpuid(1) + shr(ecx, CPUID1_ECX.SSSE3) + and(ecx, 1);
    auto idcid() => cpuid(1) + shr(ecx, CPUID1_ECX.CID) + and(ecx, 1);
    auto idsdbg() => cpuid(1) + shr(ecx, CPUID1_ECX.SDBG) + and(ecx, 1);
    auto idfma() => cpuid(1) + shr(ecx, CPUID1_ECX.FMA) + and(ecx, 1);
    auto idcx16() => cpuid(1) + shr(ecx, CPUID1_ECX.CX16) + and(ecx, 1);
    auto idxtpr() => cpuid(1) + shr(ecx, CPUID1_ECX.XTPR) + and(ecx, 1);
    auto idpdcm() => cpuid(1) + shr(ecx, CPUID1_ECX.PDCM) + and(ecx, 1);
    auto idpcid() => cpuid(1) + shr(ecx, CPUID1_ECX.PCID) + and(ecx, 1);
    auto iddca() => cpuid(1) + shr(ecx, CPUID1_ECX.DCA) + and(ecx, 1);
    auto idsse41() => cpuid(1) + shr(ecx, CPUID1_ECX.SSE4_1) + and(ecx, 1);
    auto idsse42() => cpuid(1) + shr(ecx, CPUID1_ECX.SSE4_2) + and(ecx, 1);
    auto idx2apic() => cpuid(1) + shr(ecx, CPUID1_ECX.X2APIC) + and(ecx, 1);
    auto idmovbe() => cpuid(1) + shr(ecx, CPUID1_ECX.MOVBE) + and(ecx, 1);
    auto idpopcnt() => cpuid(1) + shr(ecx, CPUID1_ECX.POPCNT) + and(ecx, 1);
    auto idtscd() => cpuid(1) + shr(ecx, CPUID1_ECX.TSCD) + and(ecx, 1);
    auto idaes() => cpuid(1) + shr(ecx, CPUID1_ECX.AES) + and(ecx, 1);
    auto idxsave() => cpuid(1) + shr(ecx, CPUID1_ECX.XSAVE) + and(ecx, 1);
    auto idosxsave() => cpuid(1) + shr(ecx, CPUID1_ECX.OSXSAVE) + and(ecx, 1);
    auto idavx() => cpuid(1) + shr(ecx, CPUID1_ECX.AVX) + and(ecx, 1);
    auto idf16c() => cpuid(1) + shr(ecx, CPUID1_ECX.F16C) + and(ecx, 1);
    auto idrdrand() => cpuid(1) + shr(ecx, CPUID1_ECX.RDRAND) + and(ecx, 1);
    auto idhv() => cpuid(1) + shr(ecx, CPUID1_ECX.HV) + and(ecx, 1);

    auto idfpu() => cpuid(1) + shr(edx, CPUID1_EDX.FPU) + and(edx, 1);
    auto idvme() => cpuid(1) + shr(edx, CPUID1_EDX.VME) + and(edx, 1);
    auto idde() => cpuid(1) + shr(edx, CPUID1_EDX.DE) + and(edx, 1);
    auto idpse() => cpuid(1) + shr(edx, CPUID1_EDX.PSE) + and(edx, 1);
    auto idtsc() => cpuid(1) + shr(edx, CPUID1_EDX.TSC) + and(edx, 1);
    auto idmsr() => cpuid(1) + shr(edx, CPUID1_EDX.MSR) + and(edx, 1);
    auto idpae() => cpuid(1) + shr(edx, CPUID1_EDX.PAE) + and(edx, 1);
    auto idcx8() => cpuid(1) + shr(edx, CPUID1_EDX.CX8) + and(edx, 1);
    auto idapic() => cpuid(1) + shr(edx, CPUID1_EDX.APIC) + and(edx, 1);
    auto idsep() => cpuid(1) + shr(edx, CPUID1_EDX.SEP) + and(edx, 1);
    auto idmtrr() => cpuid(1) + shr(edx, CPUID1_EDX.MTRR) + and(edx, 1);
    auto idpge() => cpuid(1) + shr(edx, CPUID1_EDX.PGE) + and(edx, 1);
    auto idmca() => cpuid(1) + shr(edx, CPUID1_EDX.MCA) + and(edx, 1);
    auto idcmov() => cpuid(1) + shr(edx, CPUID1_EDX.CMOV) + and(edx, 1);
    auto idpat() => cpuid(1) + shr(edx, CPUID1_EDX.PAT) + and(edx, 1);
    auto idpse36() => cpuid(1) + shr(edx, CPUID1_EDX.PSE36) + and(edx, 1);
    auto idpsn() => cpuid(1) + shr(edx, CPUID1_EDX.PSN) + and(edx, 1);
    auto idclfl() => cpuid(1) + shr(edx, CPUID1_EDX.CLFL) + and(edx, 1);
    auto idds() => cpuid(1) + shr(edx, CPUID1_EDX.DS) + and(edx, 1);
    auto idacpi() => cpuid(1) + shr(edx, CPUID1_EDX.ACPI) + and(edx, 1);
    auto idmmx() => cpuid(1) + shr(edx, CPUID1_EDX.MMX) + and(edx, 1);
    auto idfxsr() => cpuid(1) + shr(edx, CPUID1_EDX.FXSR) + and(edx, 1);
    auto idsse() => cpuid(1) + shr(edx, CPUID1_EDX.NP) + and(edx, 1);
    auto idsse2() => cpuid(1) + shr(edx, CPUID1_EDX.SSE2) + and(edx, 1);
    auto idss() => cpuid(1) + shr(edx, CPUID1_EDX.SS) + and(edx, 1);
    auto idhtt() => cpuid(1) + shr(edx, CPUID1_EDX.HTT) + and(edx, 1);
    auto idtm() => cpuid(1) + shr(edx, CPUID1_EDX.TM) + and(edx, 1);
    auto idia64() => cpuid(1) + shr(edx, CPUID1_EDX.IA64) + and(edx, 1);
    auto idpbe() => cpuid(1) + shr(edx, CPUID1_EDX.PBE) + and(edx, 1);

    /* ====== 3DNow! ====== */
    // This is an AMD exclusive vector instruction set that uses MM registers.
    // It has been deprecated and sucks, do not use this for any kind of compiler generation.

    auto pfadd(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x9e);
    auto pfsub(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x9a);
    auto pfsubr(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xaa);
    auto pfmul(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xb4);

    auto pfcmpeq(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xb0);
    auto pfcmpge(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x90);
    auto pfcmpgt(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xa0);

    auto pf2id(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x1d);
    auto pi2fd(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x0d);
    auto pf2iw(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x1c);
    auto pi2fw(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x0c);

    auto pfmax(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xa4);
    auto pfmin(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x94);

    auto pfrcp(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x96);
    auto pfrsqrt(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x97);
    auto pfrcpit1(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xa6);
    auto pfrsqit1(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xa7);
    auto pfrcpit2(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xb6);

    auto pfacc(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xae);
    auto pfnacc(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x8a);
    auto pfpnacc(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0x8e);
    auto pmulhrw(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xb7);

    auto pavgusb(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xbf);
    auto pswapd(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x0f, dst, src, 0xbb);

    auto femms() => emit!0(0x0f, 0x0e);
     
    /* ====== ICEBP ====== */
    // Intel exclusive interrupt instruction.

    auto icebp() => emit!0(0xf1);

    /* ====== PT ====== */

    auto ptwrite(RM)(RM dst) if (valid!(RM, 32)) => emit!4(0xf3, 0x0f, 0xae, dst);
    auto ptwrite(RM)(RM dst) if (valid!(RM, 64)) => emit!4(0xf3, 0x0f, 0xae, dst);

    /* ====== CLWB ====== */
    
    auto clwb(RM)(RM dst) if (valid!(RM, 8)) => emit!6(0x66, 0x0f, 0xae, dst);

    /* ====== CLFLUSHOPT ====== */
    
    auto clflushopt(RM)(RM dst) if (valid!(RM, 8)) => emit!7(0x66, 0x0f, 0xae, dst);

    /* ====== SMAP ====== */

    auto stac() => emit!0(0x0f, 0x01, 0xcb);
    auto clac() => emit!0(0x0f, 0x01, 0xca);

    /* ====== ADX ====== */

    auto adc(ubyte imm8) => emit!0(0x14, imm8);
    auto adc(ushort imm16) => emit!0(0x15, imm16);
    auto adc(uint imm32) => emit!0(0x15, imm32);
    auto adc(ulong imm32) => emit!0(0x15, cast(long)imm32);

    auto adc(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!2(0x80, dst, imm8);
    auto adc(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!2(0x81, dst, imm16);
    auto adc(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!2(0x81, dst, imm32);
    auto adc(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!2(0x81, dst, imm32);
    auto adc(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!2(0x83, dst, imm8);
    auto adc(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!2(0x83, dst, imm8);
    auto adc(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!2(0x83, dst, imm8);

    auto adc(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x10, dst, src);
    auto adc(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x11, dst, src);
    auto adc(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x11, dst, src);
    auto adc(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x11, dst, src);

    auto adc(R8 dst, Address!8 src) => emit!0(0x12, dst, src);
    auto adc(R16 dst, Address!16 src) => emit!0(0x13, dst, src);
    auto adc(R32 dst, Address!32 src) => emit!0(0x13, dst, src);
    auto adc(R64 dst, Address!64 src) => emit!0(0x13, dst, src);

    auto adcx(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0F, 0x38, 0xF6, dst, src);
    auto adcx(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0F, 0x38, 0xF6, dst, src);

    auto adox(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xF3, 0x0F, 0x38, 0xF6, dst, src);
    auto adox(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xF3, 0x0F, 0x38, 0xF6, dst, src);

    /* ====== RDSEED ====== */
    
    auto rdseed(R16 dst) => emit!7(0x0f, 0xc7, dst);
    auto rdseed(R32 dst) => emit!7(0x0f, 0xc7, dst);
    auto rdseed(R64 dst) => emit!7(0x0f, 0xc7, dst);

    /* ====== MPX ====== */

    auto bndcl(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xf3, 0x0f, 0x1a, dst, src);
    auto bndcl(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xf3, 0x0f, 0x1a, dst, src);

    auto bndcu(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xf2, 0x0f, 0x1a, dst, src);
    auto bndcu(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xf2, 0x0f, 0x1a, dst, src);

    auto bndcn(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xf2, 0x0f, 0x1b, dst, src);
    auto bndcn(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xf2, 0x0f, 0x1b, dst, src);

    auto bndldx(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!(0, NP)(0x0f, 0x1a, dst, src);
    auto bndstx(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!(0, NP)(0x0f, 0x1b, dst, src);

    auto bndmk(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xf3, 0x0f, 0x1b, dst, src);
    auto bndmk(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xf3, 0x0f, 0x1b, dst, src);

    auto bndmov(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x1a, dst, src);
    auto bndmov(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x1a, dst, src);
    auto bndmov(Address!32 dst, R32 src) => emit!0(0x0f, 0x1b, dst, src);
    auto bndmov(Address!64 dst, R32 src) => emit!0(0x0f, 0x1b, dst, src);

    auto bound(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x62, dst, src);
    auto bound(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x62, dst, src);

    /* ====== RTM ====== */
    
    auto xend() => emit!0(0x0f, 0x01, 0xd5);
    auto xabort(ubyte imm8) => emit!0(0xc6, 0xf8, imm8);
    auto xbegin(ushort rel16) => emit!0(0xc7, 0xf8, rel16);
    auto xbegin(uint rel32) => emit!0(0xc7, 0xf8, rel32);
    auto xtest() => emit!0(0x0f, 0x01, 0xd6);
    
    /* ====== INVPCID ====== */

    auto invpcid(R32 dst, Address!128 src) => emit!0(0x0f, 0x38, 0x82, dst, src);
    auto invpcid(R64 dst, Address!128 src) => emit!0(0x0f, 0x38, 0x82, dst, src);

    /* ====== HLE ====== */
        
    auto xacquire(size_t size)
    {
        // buffer = buffer[0..(buffer.length - size)]~0xf2~buffer[(buffer.length - size)..$];
        return size + 1;
    }
        
    auto xacquire_lock(size_t size)
    {
        // buffer = buffer[0..(buffer.length - size)]~0xf2~0xf0~buffer[(buffer.length - size)..$];
        return size + 2;
    }
        
    auto xrelease(size_t size)
    {
        // buffer = buffer[0..(buffer.length - size)]~0xf3~buffer[(buffer.length - size)..$];
        return size + 1;
    }

    /* ====== BMI1 ====== */

    auto tzcnt(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0xf3, 0x0f, 0xbc, dst, src);
    auto tzcnt(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xf3, 0x0f, 0xbc, dst, src);
    auto tzcnt(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xf3, 0x0f, 0xbc, dst, src);

    auto lzcnt(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0xf3, 0x0f, 0xbd, dst, src);
    auto lzcnt(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xf3, 0x0f, 0xbd, dst, src);
    auto lzcnt(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xf3, 0x0f, 0xbd, dst, src);

    auto andn(RM)(R32 dst, R32 src, RM stor) if (valid!(RM, 32)) => emit!(0, VEXI, 128, F38, 0)(0xf2, dst, src, stor);
    auto andn(RM)(R64 dst, R64 src, RM stor) if (valid!(RM, 64)) => emit!(0, VEXI, 128, F38, 0)(0xf2, dst, src, stor);

    /* ====== SGX ====== */

    auto encls() => emit!0(0x0f, 0x01, 0xcf);

    auto encls_ecreate() => mov(eax, 0) + encls();
    auto encls_eadd() => mov(eax, 1) + encls();
    auto encls_einit() => mov(eax, 2) + encls();
    auto encls_eremove() => mov(eax, 3) + encls();
    auto encls_edbgrd() => mov(eax, 4) + encls();
    auto encls_edbgwr() => mov(eax, 5) + encls();
    auto encls_eextend() => mov(eax, 6) + encls();
    auto encls_eldb() => mov(eax, 7) + encls();
    auto encls_eldu() => mov(eax, 8) + encls();
    auto encls_eblock() => mov(eax, 9) + encls();
    auto encls_epa() => mov(eax, 0xa) + encls();
    auto encls_ewb() => mov(eax, 0xb) + encls();
    auto encls_etrack() => mov(eax, 0xc) + encls();
    auto encls_eaug() => mov(eax, 0xd) + encls();
    auto encls_emodpr() => mov(eax, 0xe) + encls();
    auto encls_emodt() => mov(eax, 0xf) + encls();
    auto encls_erdinfo() => mov(eax, 0x10) + encls();
    auto encls_etrackc() => mov(eax, 0x11) + encls();
    auto encls_eldbc() => mov(eax, 0x12) + encls();
    auto encls_elduc() => mov(eax, 0x13) + encls();

    auto enclu() => emit!0(0x0f, 0x01, 0xd7);

    auto enclu_ereport() => mov(eax, 0) + enclu();
    auto enclu_egetkey() => mov(eax, 1) + enclu();
    auto enclu_eenter() => mov(eax, 2) + enclu();
    auto enclu_eresume() => mov(eax, 3) + enclu();
    auto enclu_eexit() => mov(eax, 4) + enclu();
    auto enclu_eaccept() => mov(eax, 5) + enclu();
    auto enclu_emodpe() => mov(eax, 6) + enclu();
    auto enclu_eacceptcopy() => mov(eax, 7) + enclu();
    auto enclu_edeccssa() => mov(eax, 9) + enclu();

    auto enclv() => emit!0(0x0f, 0x01, 0xc0);

    auto enclv_edecvirtchild() => mov(eax, 0) + enclv();
    auto enclv_eincvirtchild() => mov(eax, 1) + enclv();
    auto enclv_esetcontext() => mov(eax, 2) + enclv();

    /* ====== MON ====== */
    
    auto monitor() => emit!0(0x0f, 0x01, 0xc8);
    auto mwait() => emit!0(0x0f, 0x01, 0xc9);

    /* ====== VMX ====== */

    auto invvpid(R64 dst, Address!128 src) => emit!0(0x66, 0x0f, 0x38, 0x81, dst, src);
    auto invvpid(R32 dst, Address!128 src) => emit!0(0x66, 0x0f, 0x38, 0x81, dst, src);
    auto invept(R64 dst, Address!128 src) => emit!0(0x66, 0x0f, 0x38, 0x80, dst, src);
    auto invept(R32 dst, Address!128 src) => emit!0(0x66, 0x0f, 0x38, 0x80, dst, src);

    auto vmcall() => emit!0(0x0f, 0x01, 0xc1);
    auto vmfunc() => emit!0(0x0f, 0x01, 0xd4);
    auto vmclear(RM)(RM dst) if (valid!(RM, 64)) => emit!6(0x66, 0x0f, 0xc7, dst);
    auto vmlaunch() => emit!0(0x0f, 0x01, 0xc2);
    auto vmresume() => emit!0(0x0f, 0x01, 0xc3);
    auto vmxoff() => emit!0(0x0f, 0x01, 0xc4);
    auto vmxon(RM)(RM dst) if (valid!(RM, 64)) => emit!6(0xf3, 0x0f, 0xc7, dst);
    
    auto vmwrite(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!(0, NP)(0x0f, 0x79, dst, src);
    auto vmwrite(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!(0, NP)(0x0f, 0x79, dst, src);
    auto vmread(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!(0, NP)(0x0f, 0x78, dst, src);
    auto vmread(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!(0, NP)(0x0f, 0x78, dst, src);

    auto vmptrst(RM)(RM dst) if (valid!(RM, 64)) => emit!(7, NP)(0x0f, 0xc7, dst);
    auto vmptrld(RM)(RM dst) if (valid!(RM, 64)) => emit!(6, NP)(0x0f, 0xc7, dst);

    /* ====== SMX ====== */

    auto getsec() => emit!0(0x0f, 0x37);

    auto getsec_capabilities() => mov(eax, 0) + getsec();
    auto getsec_enteraccs() => mov(eax, 2) + getsec();
    auto getsec_exitac() => mov(eax, 3) + getsec();
    auto getsec_senter() => mov(eax, 4) + getsec();
    auto getsec_sexit() => mov(eax, 5) + getsec();
    auto getsec_parameters() => mov(eax, 6) + getsec();
    auto getsec_smctrl() => mov(eax, 7) + getsec();
    auto getsec_wakeup() => mov(eax, 8) + getsec();

    /* ====== CX16 ====== */

    auto cmpxchg16b(Address!128 dst) => emit!1(0x48, 0x0f, 0xc7, dst);

    /* ====== POPCNT ====== */
    
    auto popcnt(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0xf3, 0x0f, 0xb8, dst, src);
    auto popcnt(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xf3, 0x0f, 0xb8, dst, src);
    auto popcnt(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xf3, 0x0f, 0xb8, dst, src);
    
    /* ====== XSAVE ====== */
    
    auto xgetbv() => emit!0(0x0f, 0x01, 0xd0);
    auto xsetbv() => emit!0(0x0f, 0x01, 0xd1);

    auto xrstor(RM)(RM dst) if (isInstanceOf!(Address, RM)) => emit!(5, NP)(0x0f, 0xae, dst);
    auto xsave(RM)(RM dst) if (isInstanceOf!(Address, RM)) => emit!(4, NP)(0x0f, 0xae, dst);

    auto xrstors(RM)(RM dst) if (isInstanceOf!(Address, RM)) => emit!(3, NP)(0x0f, 0xc7, dst);
    auto xsaves(RM)(RM dst) if (isInstanceOf!(Address, RM)) => emit!(5, NP)(0x0f, 0xc7, dst);

    auto xsaveopt(RM)(RM dst) if (isInstanceOf!(Address, RM)) => emit!(6, NP)(0x0f, 0xae, dst);
    auto xsavec(RM)(RM dst) if (isInstanceOf!(Address, RM)) => emit!(4, NP)(0x0f, 0xc7, dst);

    /* ====== RDRAND ====== */

    auto rdrand(R16 dst) => emit!6(0x0f, 0xc7, dst);
    auto rdrand(R32 dst) => emit!6(0x0f, 0xc7, dst);
    auto rdrand(R64 dst) => emit!6(0x0f, 0xc7, dst);

    /* ====== FPU ====== */

    auto fabs() => emit!0(0xd9, 0xe1);
    auto fchs() => emit!0(0xd9, 0xe0);

    auto fclex() => emit!0(0x9b, 0xdb, 0xe2);
    auto fnclex() => emit!0(0xdb, 0xe2);

    auto fadd(Address!32 dst) => emit!(0, NP)(0xd8, dst);
    auto fadd(Address!64 dst) => emit!(0, NP)(0xdc, dst);
    auto fadd(ST dst, ST src)
    {
        if (dst.index == 0)
            emit!(0, NRM)(0xd8, 0xc0, src);
        else if (src.index == 0)
            emit!(0, NRM)(0xdc, 0xc0, dst);
        else
            assert(0, "Cannot encode 'fadd' with no 'st0' operand!");
    }
    auto faddp(ST dst) => emit!(0, NRM)(0xde, 0xc0, dst);
    auto fiadd(Address!32 dst) => emit!(0, NP)(0xda, dst);
    auto fiadd(Address!16 dst) => emit!(0, NP)(0xde, dst);

    auto fbld(Address!80 dst) => emit!(4, NP)(0xdf, dst);
    auto fbstp(Address!80 dst) => emit!(6, NP)(0xdf, dst);

    auto fcom(Address!32 dst) => emit!(2, NP)(0xd8, dst);
    auto fcom(Address!64 dst) => emit!(2, NP)(0xdc, dst);
    auto fcom(ST dst) => emit!(2, NRM)(0xd8, 0xd0, dst);

    auto fcomp(Address!32 dst) => emit!(3, NP)(0xd8, dst);
    auto fcomp(Address!64 dst) => emit!(3, NP)(0xdc, dst);
    auto fcomp(ST dst) => emit!(2, NRM)(0xd8, 0xd8, dst);
    auto fcompp() => emit!0(0xde, 0xd9);

    auto fcomi(ST dst) => emit!(0, NRM)(0xdb, 0xf0, dst);
    auto fcomip(ST dst) => emit!(0, NRM)(0xdf, 0xf0, dst);
    auto fucomi(ST dst) => emit!(0, NRM)(0xdb, 0xe8, dst);
    auto fucomip(ST dst) => emit!(0, NRM)(0xdf, 0xe8, dst);

    auto ficom(Address!16 dst) => emit!(2, NP)(0xde, dst);
    auto ficom(Address!32 dst) => emit!(2, NP)(0xda, dst);
    auto ficomp(Address!16 dst) => emit!(2, NP)(0xde, dst);
    auto ficomp(Address!32 dst) => emit!(2, NP)(0xda, dst);
    
    auto fucom(ST dst) => emit!(2, NRM)(0xdd, 0xe0, dst);
    auto fucomp(ST dst) => emit!(2, NRM)(0xdd, 0xe8, dst);
    auto fucompp() => emit!0(0xda, 0xe9);

    auto ftst() => emit!0(0xd9, 0xe4);

    auto f2xm1() => emit!0(0xd9, 0xf0);
    auto fyl2x() => emit!0(0xd9, 0xf1);
    auto fyl2xp1() => emit!0(0xd9, 0xf9);

    auto fcos() => emit!0(0xd9, 0xff);
    auto fsin() => emit!0(0xd9, 0xfe);
    auto fsincos() => emit!0(0xd9, 0xfb);
    auto fsqrt() => emit!0(0xd9, 0xfa);
    
    auto fptan() => emit!0(0xd9, 0xf2);
    auto fpatan() => emit!0(0xd9, 0xf3);
    auto fprem() => emit!0(0xd9, 0xf8);
    auto fprem1() => emit!0(0xd9, 0xf5);

    auto fdecstp() => emit!0(0xd9, 0xf6);
    auto fincstp() => emit!0(0xd9, 0xf7);

    auto fild(Address!16 dst) => emit!(0, NP)(0xdf, dst);
    auto fild(Address!32 dst) => emit!(0, NP)(0xdb, dst);
    auto fild(Address!64 dst) => emit!(5, NP)(0xdf, dst);

    auto fist(Address!16 dst) => emit!(2, NP)(0xdf, dst);
    auto fist(Address!32 dst) => emit!(2, NP)(0xdb, dst);

    auto fistp(Address!16 dst) => emit!(3, NP)(0xdf, dst);
    auto fistp(Address!32 dst) => emit!(3, NP)(0xdb, dst);
    auto fistp(Address!64 dst) => emit!(7, NP)(0xdf, dst);

    auto fisttp(Address!16 dst) => emit!(1, NP)(0xdf, dst);
    auto fisttp(Address!32 dst) => emit!(1, NP)(0xdb, dst);
    auto fisttp(Address!64 dst) => emit!(1, NP)(0xdd, dst);

    auto fldcw(Address!16 dst) => emit!(5, NP)(0xd9, dst);
    auto fstcw(Address!16 dst) => emit!(7, NP)(0x9b, 0xd9, dst);
    auto fnstcw(Address!16 dst) => emit!(7, NP)(0xd9, dst);

    auto fldenv(Address!112 dst) => emit!(4, NP)(0xd9, dst);
    auto fldenv(Address!224 dst) => emit!(4, NP)(0xd9, dst);
    auto fstenv(Address!112 dst) => emit!(6, NP)(0x9b, 0xd9, dst);
    auto fstenv(Address!224 dst) => emit!(6, NP)(0x9b, 0xd9, dst);
    auto fnstenv(Address!112 dst) => emit!(6, NP)(0xd9, dst);
    auto fnstenv(Address!224 dst) => emit!(6, NP)(0xd9, dst);

    auto fstsw(Address!16 dst) => emit!(7, NP)(0x9b, 0xdd, dst);
    auto fstsw() => emit!0(0x9b, 0xdf, 0xe0);
    auto fnstsw(Address!16 dst) => emit!(7, NP)(0xdd, dst);
    auto fnstsw() => emit!0(0xdf, 0xe0);

    auto fld(Address!32 dst) => emit!(0, NP)(0xd9, dst);
    auto fld(Address!64 dst) => emit!(0, NP)(0xdd, dst);
    auto fld(Address!80 dst) => emit!(5, NP)(0xdb, dst);
    auto fld(ST dst) => emit!(0, NRM)(0xd9, 0xc0, dst);

    auto fld1() => emit!0(0xd9, 0xe8);
    auto fldl2t() => emit!0(0xd9, 0xe9);
    auto fldl2e() => emit!0(0xd9, 0xea);
    auto fldpi() => emit!0(0xd9, 0xeb);
    auto fldlg2() => emit!0(0xd9, 0xec);
    auto fldln2() => emit!0(0xd9, 0xed);
    auto fldz() => emit!0(0xd9, 0xee);

    auto fst(Address!32 dst) => emit!(2, NP)(0xd9, dst);
    auto fst(Address!64 dst) => emit!(2, NP)(0xdd, dst);
    auto fst(ST dst) => emit!(0, NRM)(0xdd, 0xd0, dst);
    
    auto fstp(Address!32 dst) => emit!(3, NP)(0xd9, dst);
    auto fstp(Address!64 dst) => emit!(3, NP)(0xdd, dst);
    auto fstp(Address!80 dst) => emit!(7, NP)(0xdb, dst);
    auto fstp(ST dst) => emit!(0, NRM)(0xdd, 0xd8, dst);

    auto fdiv(Address!32 dst) => emit!(6, NP)(0xd8, dst);
    auto fdiv(Address!64 dst) => emit!(6, NP)(0xdc, dst);
    auto fdiv(ST dst, ST src)
    {
        if (dst.index == 0)
            emit!(0, NRM)(0xd8, 0xf0, src);
        else if (src.index == 0)
            emit!(0, NRM)(0xdc, 0xf8, dst);
        else
            assert(0, "Cannot encode 'fadd' with no 'st0' operand!");
    }
    auto fdivp(ST dst) => emit!(0, NRM)(0xde, 0xf8, dst);
    auto fidiv(Address!32 dst) => emit!(6, NP)(0xda, dst);
    auto fidiv(Address!16 dst) => emit!(6, NP)(0xde, dst);

    auto fdivr(Address!32 dst) => emit!(7, NP)(0xd8, dst);
    auto fdivr(Address!64 dst) => emit!(7, NP)(0xdc, dst);
    auto fdivr(ST dst, ST src)
    {
        if (dst.index == 0)
            emit!(0, NRM)(0xd8, 0xf8, src);
        else if (src.index == 0)
            emit!(0, NRM)(0xdc, 0xf0, dst);
        else
            assert(0, "Cannot encode 'fadd' with no 'st0' operand!");
    }
    auto fdivrp(ST dst) => emit!(0, NRM)(0xde, 0xf0, dst);
    auto fidivr(Address!32 dst) => emit!(7, NP)(0xda, dst);
    auto fidivr(Address!16 dst) => emit!(7, NP)(0xde, dst);

    auto fscale() => emit!0(0xd9, 0xfd);
    auto frndint() => emit!0(0xd9, 0xfc);
    auto fexam() => emit!0(0xd9, 0xe5);
    auto ffree(ST dst) => emit!(0, NRM)(0xdd, 0xc0, dst);
    auto fxch(ST dst) => emit!(0, NRM)(0xd9, 0xc8, dst);
    auto fxtract() => emit!0(0xd9, 0xf4);

    auto fnop() => emit!0(0xd9, 0xd0);
    auto fninit() => emit!0(0x9b, 0xdb, 0xe3);
    auto finit() => emit!0(0xdb, 0xe3);

    auto fsave(Address!752 dst) => emit!6(0x9b, 0xdd, dst);
    auto fsave(Address!864 dst) => emit!6(0x9b, 0xdd, dst);
    auto fnsave(Address!752 dst) => emit!6(0xdd, dst);
    auto fnsave(Address!864 dst) => emit!6(0xdd, dst);

    auto frstor(Address!752 dst) => emit!4(0xdd, dst);
    auto frstor(Address!864 dst) => emit!4(0xdd, dst);

    static if (!X64)
    auto fxsave(Address!4096 dst) => emit!(0, NP)(0x0f, 0xae, dst);
    static if (X64)
    auto fxsave(Address!4096 dst) => emit!(0, NP)(0x48, 0x0f, 0xae, dst);
    
    static if (!X64)
    auto fxrstor(Address!4096 dst) => emit!(1, NP)(0x0f, 0xae, dst);
    static if (X64)
    auto fxrstor(Address!4096 dst) => emit!(1, NP)(0x48, 0x0f, 0xae, dst);

    auto fmul(Address!32 dst) => emit!(1, NP)(0xd8, dst);
    auto fmul(Address!64 dst) => emit!(1, NP)(0xdc, dst);
    auto fmul(ST dst, ST src)
    {
        if (dst.index == 0)
            emit!(0, NRM)(0xd8, 0xc8, src);
        else if (src.index == 0)
            emit!(0, NRM)(0xdc, 0xc8, dst);
        else
            assert(0, "Cannot encode 'fadd' with no 'st0' operand!");
    }
    auto fmulp(ST dst) => emit!(0, NRM)(0xde, 0xc8, dst);
    auto fimul(Address!32 dst) => emit!(1, NP)(0xda, dst);
    auto fimul(Address!16 dst) => emit!(1, NP)(0xde, dst);

    auto fsub(Address!32 dst) => emit!(4, NP)(0xd8, dst);
    auto fsub(Address!64 dst) => emit!(4, NP)(0xdc, dst);
    auto fsub(ST dst, ST src)
    {
        if (dst.index == 0)
            emit!(0, NRM)(0xd8, 0xe0, src);
        else if (src.index == 0)
            emit!(0, NRM)(0xdc, 0xe8, dst);
        else
            assert(0, "Cannot encode 'fadd' with no 'st0' operand!");
    }
    auto fsubp(ST dst) => emit!(0, NRM)(0xde, 0xe8, dst);
    auto fisub(Address!32 dst) => emit!(4, NP)(0xda, dst);
    auto fisub(Address!16 dst) => emit!(4, NP)(0xde, dst);

    auto fsubr(Address!32 dst) => emit!(5, NP)(0xd8, dst);
    auto fsubr(Address!64 dst) => emit!(5, NP)(0xdc, dst);
    auto fsubr(ST dst, ST src)
    {
        if (dst.index == 0)
            emit!(0, NRM)(0xd8, 0xe8, src);
        else if (src.index == 0)
            emit!(0, NRM)(0xdc, 0xe0, dst);
        else
            assert(0, "Cannot encode 'fadd' with no 'st0' operand!");
    }
    auto fsubrp(ST dst) => emit!(0, NRM)(0xde, 0xe0, dst);
    auto fisubr(Address!32 dst) => emit!(5, NP)(0xda, dst);
    auto fisubr(Address!16 dst) => emit!(5, NP)(0xde, dst);

    auto fcmovb(ST dst) => emit!(0, NRM)(0xda, 0xc0, dst);
    auto fcmove(ST dst) => emit!(0, NRM)(0xda, 0xc8, dst);
    auto fcmovbe(ST dst) => emit!(0, NRM)(0xda, 0xd0, dst);
    auto fcmovu(ST dst) => emit!(0, NRM)(0xda, 0xd8, dst);
    auto fcmovnb(ST dst) => emit!(0, NRM)(0xdb, 0xc0, dst);
    auto fcmovne(ST dst) => emit!(0, NRM)(0xdb, 0xc8, dst);
    auto fcmovnbe(ST dst) => emit!(0, NRM)(0xdb, 0xd0, dst);
    auto fcmovnu(ST dst) => emit!(0, NRM)(0xdb, 0xd8, dst);

    /* ====== TSC ====== */

    auto rdtsc() => emit!0(0x0f, 0x31);
    auto rdtscp() => emit!0(0x0f, 0x01, 0xf9);

    /* ====== MSR ====== */

    auto rdmsr() => emit!0(0x0f, 0x32);
    auto wrmsr() => emit!0(0x0f, 0x30);
    
    /* ====== CX8 ====== */

    auto cmpxchg8b(Address!64 dst) => emit!(1, NP)(0x0f, 0xc7, dst);

    /* ====== SEP ====== */
    
    auto sysenter() => emit!0(0x0f, 0x34);
    auto sysexitc() => emit!0(0x0f, 0x35);
    auto sysexit() => emit!0(0x0f, 0x35);

    /* ====== CMOV ====== */

    auto cmova(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x47, src, dst);
    auto cmova(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x47, src, dst);
    auto cmova(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x47, src, dst);
    
    auto cmovae(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x43, src, dst);
    auto cmovae(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x43, src, dst);
    auto cmovae(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x43, src, dst);
    
    auto cmovb(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x42, src, dst);
    auto cmovb(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x42, src, dst);
    auto cmovb(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x42, src, dst);
    
    auto cmovbe(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x46, src, dst);
    auto cmovbe(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x46, src, dst);
    auto cmovbe(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x46, src, dst);
    
    auto cmovc(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x42, src, dst);
    auto cmovc(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x42, src, dst);
    auto cmovc(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x42, src, dst);
    
    auto cmove(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x44, src, dst);
    auto cmove(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x44, src, dst);
    auto cmove(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x44, src, dst);
    
    auto cmovg(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4f, src, dst);
    auto cmovg(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4f, src, dst);
    auto cmovg(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4f, src, dst);
    
    auto cmovge(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4d, src, dst);
    auto cmovge(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4d, src, dst);
    auto cmovge(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4d, src, dst);
    
    auto cmovl(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4c, src, dst);
    auto cmovl(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4c, src, dst);
    auto cmovl(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4c, src, dst);
    
    auto cmovle(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4e, src, dst);
    auto cmovle(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4e, src, dst);
    auto cmovle(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4e, src, dst);
    
    auto cmovna(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x46, src, dst);
    auto cmovna(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x46, src, dst);
    auto cmovna(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x46, src, dst);
    
    auto cmovnae(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x42, src, dst);
    auto cmovnae(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x42, src, dst);
    auto cmovnae(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x42, src, dst);
    
    auto cmovnb(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x43, src, dst);
    auto cmovnb(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x43, src, dst);
    auto cmovnb(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x43, src, dst);
    
    auto cmovnbe(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x47, src, dst);
    auto cmovnbe(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x47, src, dst);
    auto cmovnbe(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x47, src, dst);
    
    auto cmovnc(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x43, src, dst);
    auto cmovnc(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x43, src, dst);
    auto cmovnc(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x43, src, dst);
    
    auto cmovne(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x45, src, dst);
    auto cmovne(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x45, src, dst);
    auto cmovne(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x45, src, dst);
    
    auto cmovng(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4e, src, dst);
    auto cmovng(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4e, src, dst);
    auto cmovng(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4e, src, dst);
    
    auto cmovnge(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4c, src, dst);
    auto cmovnge(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4c, src, dst);
    auto cmovnge(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4c, src, dst);
    
    auto cmovnl(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4d, src, dst);
    auto cmovnl(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4d, src, dst);
    auto cmovnl(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4d, src, dst);
    
    auto cmovnle(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4f, src, dst);
    auto cmovnle(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4f, src, dst);
    auto cmovnle(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4f, src, dst);
    
    auto cmovno(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x41, src, dst);
    auto cmovno(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x41, src, dst);
    auto cmovno(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x41, src, dst);
    
    auto cmovnp(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4b, src, dst);
    auto cmovnp(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4b, src, dst);
    auto cmovnp(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4b, src, dst);
    
    auto cmovns(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x49, src, dst);
    auto cmovns(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x49, src, dst);
    auto cmovns(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x49, src, dst);
    
    auto cmovnz(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x45, src, dst);
    auto cmovnz(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x45, src, dst);
    auto cmovnz(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x45, src, dst);
    
    auto cmovo(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x40, src, dst);
    auto cmovo(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x40, src, dst);
    auto cmovo(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x40, src, dst);
    
    auto cmovp(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4a, src, dst);
    auto cmovp(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4a, src, dst);
    auto cmovp(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4a, src, dst);
    
    auto cmovpe(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4a, src, dst);
    auto cmovpe(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4a, src, dst);
    auto cmovpe(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4a, src, dst);
    
    auto cmovpo(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x4b, src, dst);
    auto cmovpo(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x4b, src, dst);
    auto cmovpo(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x4b, src, dst);
    
    auto cmovs(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x48, src, dst);
    auto cmovs(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x48, src, dst);
    auto cmovs(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x48, src, dst);
    
    auto cmovz(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x44, src, dst);
    auto cmovz(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0x44, src, dst);
    auto cmovz(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x44, src, dst);

    /* ====== CLFL ====== */

    auto clflush(RM)(RM dst) if (valid!(RM, 8)) => emit!(7, NP)(0x0f, 0xae, dst);

    /* ====== HRESET ====== */

    auto hreset(ubyte imm8) => emit!0(0xf3, 0x0f, 0x3a, 0xf0, 0xc0, imm8, eax);

    /* ====== CET ====== */
    // Shadow stack instruction set.

    auto incsspd(R32 dst) => emit!5(0xf3, 0x0f, 0xae, dst);
    auto incsspq(R64 dst) => emit!5(0xf3, 0x0f, 0xae, dst);
    auto clrssbsy(Address!64 dst) => emit!6(0xf3, 0x0f, 0xae, dst);
    auto setssbsy() => emit!0(0xf3, 0x0f, 0x01, 0xe8);

    auto rdsspd(R32 dst) => emit!1(0xf3, 0x0f, 0x1e, dst);
    auto rdsspq(R64 dst) => emit!1(0xf3, 0x0f, 0x1e, dst);
    auto wrssd(Address!32 dst, R32 src) => emit!0(0xf3, 0x38, 0xf6, dst, src);
    auto wrssq(Address!64 dst, R64 src) => emit!0(0xf3, 0x38, 0xf6, dst, src);
    auto wrussd(Address!32 dst, R32 src) => emit!1(0x66, 0xf3, 0x38, 0xf5, dst, src);
    auto wrussq(Address!64 dst, R64 src) => emit!1(0x66, 0xf3, 0x38, 0xf5, dst, src);

    auto rstorssp(Address!64 dst) => emit!5(0xf3, 0x0f, 0x01, dst);
    auto saveprevssp() => emit!5(0xf3, 0x0f, 0x01, 0xae, edx);

    auto endbr32() => emit!0(0xf3, 0x0f, 0x1e, 0xfb);
    auto endbr64() => emit!0(0xf3, 0x0f, 0x1e, 0xfa);

    /* ====== FSGSBASE ====== */

    auto rdfsbase(R32 dst) => emit!0(0xf3, 0x0f, 0xae, dst);
    auto rdfsbase(R64 dst) => emit!0(0xf3, 0x0f, 0xae, dst);
    auto rdgsbase(R32 dst) => emit!1(0xf3, 0x0f, 0xae, dst);
    auto rdgsbase(R64 dst) => emit!1(0xf3, 0x0f, 0xae, dst);

    auto wrfsbase(R32 dst) => emit!2(0xf3, 0x0f, 0xae, dst);
    auto wrfsbase(R64 dst) => emit!2(0xf3, 0x0f, 0xae, dst);
    auto wrgsbase(R32 dst) => emit!3(0xf3, 0x0f, 0xae, dst);
    auto wrgsbase(R64 dst) => emit!3(0xf3, 0x0f, 0xae, dst);

    /* ====== RDPID ====== */

    auto rdpid(R32 dst) => emit!7(0xf3, 0x0f, 0xc7, dst);
    auto rdpid(R64 dst) => emit!7(0xf3, 0x0f, 0xc7, dst);

    /* ====== OSPKE ====== */

    auto wrpkru() => emit!0(0x0f, 0x01, 0xef);
    auto rdpkru() => emit!0(0x0f, 0x01, 0xee);

    /* ====== UINTR ====== */

    auto testui() => emit!0(0xf3, 0x0f, 0x01, 0xed);
    auto stui() => emit!0(0xf3, 0x0f, 0x01, 0xef);
    auto clui() => emit!0(0xf3, 0x0f, 0x01, 0xee);
    auto uiret() => emit!0(0xf3, 0x0f, 0x01, 0xec);
    auto senduipi(RM)(RM dst) if (valid!(RM, 8) || valid!(RM, 16) || valid!(RM, 32) || valid!(RM, 64)) => emit!6(0xf3, 0x0f, 0xc7, dst);

    /* ====== WAITPKG ====== */
    
    auto umwait(R32 dst) => emit!6(0xf2, 0x0f, 0xae, dst);
    auto umonitor(R16 dst) => emit!6(0xf3, 0x0f, 0xae, dst);
    auto umonitor(R32 dst) => emit!6(0xf3, 0x0f, 0xae, dst);
    auto umonitor(R64 dst) => emit!6(0xf3, 0x0f, 0xae, dst);
    auto tpause(R32 dst) => emit!6(0x0f, 0xae, dst);

    /* ====== CLDEMOTE ====== */
    
    auto cldemote(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x1c, dst);

    /* ====== TSXLDTRK ====== */

    auto xresldtrk() => emit!0(0xf2, 0x0f, 0x01, 0xe9);
    auto xsusldtrk() => emit!0(0xf2, 0x0f, 0x01, 0xe8);

    /* ====== SERALIZE ====== */
    
    auto serialize() => emit!0(0x0f, 0x01, 0xe8);

    /* ====== PCONFIG ====== */

    auto pconfig() => emit!0(0x0f, 0x01, 0xc5);

    /* ====== PMC ====== */

    auto rdpmc() => emit!0(0x0f, 0x33); 

    /* ====== UMIP ====== */

    auto wbinvd() => emit!0(0x0f, 0x09);
    auto wbnoinvd() => emit!0(0xf3, 0x0f, 0x09);
    
    auto invd() => emit!0(0x0f, 0x08);

    auto lgdt(RM)(RM dst) if (valid!(RM, 32)) => emit!2(0x0f, 0x01, dst);
    auto lgdt(RM)(RM dst) if (valid!(RM, 64)) => emit!2(0x0f, 0x01, dst);
    auto sgdt(RM)(RM dst) if (valid!(RM, 64)) => emit!0(0x0f, 0x01, dst);

    auto lldt(RM)(RM dst) if (valid!(RM, 16)) => emit!2(0x0f, 0x00, dst);
    auto sldt(RM)(RM dst) if (valid!(RM, 16)) => emit!0(0x0f, 0x00, dst);

    auto lidt(RM)(RM dst) if (valid!(RM, 32)) => emit!3(0x0f, 0x01, dst);
    auto lidt(RM)(RM dst) if (valid!(RM, 64)) => emit!3(0x0f, 0x01, dst);
    auto sidt(RM)(RM dst) if (valid!(RM, 64)) => emit!1(0x0f, 0x01, dst);

    auto lmsw(RM)(RM dst) if (valid!(RM, 16)) => emit!6(0x0f, 0x01, dst);

    auto smsw(RM)(RM dst) if (valid!(RM, 16)) => emit!4(0x0f, 0x01, dst);
    auto smsw(RM)(RM dst) if (valid!(RM, 32)) => emit!4(0x0f, 0x01, dst);
    auto smsw(RM)(RM dst) if (valid!(RM, 64)) => emit!4(0x0f, 0x01, dst);

    /* ====== PCID ====== */

    auto invlpg(RM)(RM dst) if (valid!(RM, 64)) => emit!7(0x0f, 0x01, dst);

    /* ====== LAHF-SAHF ====== */

    auto sahf() => emit!0(0x9e);
    auto lahf() => emit!0(0x9f);

    /* ====== BMI2 ====== */

    auto sarx(RM)(R32 dst, RM src, R32 cnt) if (valid!(RM, 32)) => emit!(0, VEXI, 128, F38, 0xf3)(0xf7, dst, src, cnt);
    auto shlx(RM)(R32 dst, RM src, R32 cnt) if (valid!(RM, 32)) => emit!(0, VEXI, 128, F38, 0x66)(0xf7, dst, src, cnt);
    auto shrx(RM)(R32 dst, RM src, R32 cnt) if (valid!(RM, 32)) => emit!(0, VEXI, 128, F38, 0xf2)(0xf7, dst, src, cnt);

    auto sarx(RM)(R64 dst, RM src, R64 cnt) if (valid!(RM, 64)) => emit!(0, VEXI, 128, F38, 0xf3)(0xf7, dst, src, cnt);
    auto shlx(RM)(R64 dst, RM src, R64 cnt) if (valid!(RM, 64)) => emit!(0, VEXI, 128, F38, 0x66)(0xf7, dst, src, cnt);
    auto shrx(RM)(R64 dst, RM src, R64 cnt) if (valid!(RM, 64)) => emit!(0, VEXI, 128, F38, 0xf2)(0xf7, dst, src, cnt);

    /* ====== MMX ====== */

    auto movq(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!(0, SSE)(0x0f, 0x6f, dst, src);
    auto movq(Address!64 dst, MMX src) => emit!(0, SSE)(0x0f, 0x7f, dst, src);

    auto movd(RM)(MMX dst, RM src) if (valid!(RM, 32)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0x0f, 0x6e, dst, src);
    auto movd(RM)(RM dst, MMX src) if (valid!(RM, 32)) => emit!(0, SSE)(0x0f, 0x7e, dst, src);

    auto movq(RM)(MMX dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0x6e, dst, src);
    auto movq(RM)(RM dst, MMX src) if (valid!(RM, 64)) => emit!0(0x0f, 0x7e, dst, src);

    /* ====== SSE ====== */

    auto roundsd(RM)(XMM dst, RM src, ubyte imm8) if (valid!(RM, 128, 64)) => emit!(0, SSE)(0x66, 0x0f, 0x3a, 0x0b, dst, src, imm8);
    auto xorpd(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x57, dst, src);
    auto addpd(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x58, dst, src);
    auto addps(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x58, dst, src);
    auto addss(RM)(XMM dst, RM src) if (valid!(RM, 128, 32)) => emit!(0, SSE)(0xf3, 0x0f, 0x58, dst, src);
    auto addsd(RM)(XMM dst, RM src) if (valid!(RM, 128, 32)) => emit!(0, SSE)(0xf2, 0x0f, 0x58, dst, src);

    auto andpd(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x54, dst, src);
    auto andpd(RM)(XMM dst, long src) => emit!(0, SSE)(0x66, 0x0f, 0x54, dst, src);

    auto pxor(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0xef, dst, src);
    
    auto mulss(RM)(XMM dst, RM src) if (valid!(RM, 128, 32)) => emit!(0, SSE)(0xf3, 0x0f, 0x59, dst, src);
    auto mulsd(RM)(XMM dst, RM src) if (valid!(RM, 128, 64)) => emit!(0, SSE)(0xf2, 0x0f, 0x59, dst, src);
    auto mulps(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x59, dst, src);
    auto mulpd(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x59, dst, src);

    auto divss(RM)(XMM dst, RM src) if (valid!(RM, 128, 32)) => emit!(0, SSE)(0xf3, 0x0f, 0x5e, dst, src);
    auto divsd(RM)(XMM dst, RM src) if (valid!(RM, 128, 64)) => emit!(0, SSE)(0xf2, 0x0f, 0x5e, dst, src);
    auto divps(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x5e, dst, src);
    auto divpd(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x5e, dst, src);

    auto cvtss2sd(RM)(XMM dst, RM src) if (valid!(RM, 128, 32)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0xf3, 0x0f, 0x5a, dst, src);
    auto cvtsd2ss(RM)(XMM dst, RM src) if (valid!(RM, 128, 64)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0xf2, 0x0f, 0x5a, dst, src);
    auto cvtss2si(RM)(RM dst, XMM src) if (valid!(RM, 32)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0xf3, 0x0f, 0x2d, dst, src);
    auto cvtsd2si(RM)(RM dst, XMM src) if (valid!(RM, 64)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0xf2, 0x0f, 0x2d, dst, src);
    auto cvtsi2ss(RM)(XMM dst, RM src) if (valid!(RM, 32)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0xf3, 0x0f, 0x2a, dst, src);
    auto cvtsi2sd(RM)(XMM dst, RM src) if (valid!(RM, 64)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0xf2, 0x0f, 0x2a, dst, src);
    auto comiss(XMM src1, XMM src2) => emit!(0, SSE)(0x0f, 0x2f, src1, src2);
    auto ucomiss(XMM src1, XMM src2) => emit!(0, SSE)(0x0f, 0x2e, src1, src2);
    auto comisd(XMM src1, XMM src2) => emit!(0, SSE)(0x66, 0x0f, 0x2f, src1, src2);
    auto ucomisd(XMM src1, XMM src2) => emit!(0, SSE)(0x66, 0x0f, 0x2e, src1, src2);

    auto subsd(RM)(XMM dst, RM src) if (valid!(RM, 128, 64)) => emit!(0, SSE)(0xf2, 0x0f, 0x5c, dst, src);
    auto subss(RM)(XMM dst, RM src) if (valid!(RM, 128, 32)) => emit!(0, SSE)(0xf3, 0x0f, 0x5c, dst, src);
    auto subps(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x5c, dst, src);
    auto subpd(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x5c, dst, src);

    auto rcpss(RM)(XMM dst, RM src) if (valid!(RM, 128, 32)) => emit!(0, SSE)(0xf3, 0x0f, 0x53, dst, src);
    /* ====== SSE2 ====== */

    auto punpcklqdq(XMM dst, XMM src) => emit!(0, SSE)(0x66, 0x0f, 0x6c, dst, src);
    auto unpcklpd(XMM dst, XMM src) => emit!(0, SSE)(0x66, 0x0f, 0x14, dst, src);
    auto shufps(XMM dst, XMM src, ubyte imm8) => emit!(0, SSE)(0x0f, 0xc6, dst, src, imm8);
    auto shufpd(XMM dst, XMM src, ubyte imm8) => emit!(0, SSE)(0x66, 0x0f, 0xc6, dst, src, imm8);

    auto lfence() => emit!0(0x0f, 0xae, 0xe8);
    auto sfence() => emit!0(0x0f, 0xae, 0xf8);
    auto mfence() => emit!0(0x0f, 0xae, 0xf0);

    auto movq(RM)(XMM dst, RM src) if (valid!(RM, 128, 64)) => emit!(0, SSE)(0xf3, 0x0f, 0x7e, dst, src);
    auto movq(Address!64 dst, XMM src) => emit!(0, SSE)(0x66, 0x0f, 0xd6, dst, src);

    auto movd(RM)(XMM dst, RM src) if (valid!(RM, 32)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0x66, 0x0f, 0x6e, dst, src);
    auto movd(RM)(RM dst, XMM src) if (valid!(RM, 32)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0x66, 0x0f, 0x7e, src, dst);
    // TODO: This won't flip dst and src but should also also should generate a REX
    auto movq(RM)(XMM dst, RM src) if (valid!(RM, 64)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0x66, 0x0f, 0x6e, dst, src);
    auto movq(RM)(RM dst, XMM src) if (valid!(RM, 64)) => emit!(0, SSE, 128, DEFAULT, 0, true)(0x66, 0x0f, 0x7e, src, dst);

    auto movupd(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x10, dst, src);
    auto movupd(RM)(RM dst, XMM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x11, src, dst);

    auto rsqrtss(RM)(XMM dst, RM src) if (valid!(RM, 128, 64)) => emit!(0, SSE)(0xf3, 0x0f, 0x52, dst, src);
    /* ====== SSE3 ====== */

    auto addsubps(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0xf2, 0x0f, 0xd0, dst, src);
    auto addsubpd(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0xd0, dst, src);
    auto blendpd(RM)(XMM dst, RM src, ubyte imm8) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x3a, 0x0d, dst, src, imm8);
    /* ====== AVX ====== */

    // auto shufpd(XMM dst, XMM src, ubyte imm8) => emit!(0, VEX, 128, DEFAULT, 0x66)(0xc6, dst, src, imm8);
    auto vshufpd(XMM dst, XMM src1, XMM src2, ubyte imm8) => emit!(0, VEX, 128, DEFAULT, 0x66)(0xc6, dst, src1, src2, imm8);
    auto vpbroadcastq(XMM dst, XMM src) => emit!(0, VEX, 128, F38, 0x66)(0x59, dst, src);
    auto vpbroadcastd(XMM dst, XMM src) => emit!(0, VEX, 128, F38, 0x66)(0x58, dst, src);
    auto vaddpd(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128)) => emit!(0, VEX, 128, DEFAULT, 0x66)(0x58, dst, src, stor);
    auto vaddpd(RM)(YMM dst, YMM src, RM stor) if (valid!(RM, 256)) => emit!(0, VEX, 256, DEFAULT, 0x66)(0x58, dst, src, stor);
     
    auto vaddps(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128)) => emit!(0, VEX, 128, DEFAULT, 0)(0x58, dst, src, stor);
    auto vaddps(RM)(YMM dst, YMM src, RM stor) if (valid!(RM, 256)) => emit!(0, VEX, 256, DEFAULT, 0)(0x58, dst, src, stor);

    auto vaddsd(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128, 64)) => emit!(0, VEX, 128, DEFAULT, 0xf2)(0x58, dst, src, stor);
    auto vaddss(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128, 32)) => emit!(0, VEX, 128, DEFAULT, 0xf3)(0x58, dst, src, stor);

    auto vaddsubpd(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128)) => emit!(0, VEX, 128, DEFAULT, 0x66)(0xd0, dst, src, stor);
    auto vaddsubpd(RM)(YMM dst, YMM src, RM stor) if (valid!(RM, 256)) => emit!(0, VEX, 256, DEFAULT, 0x66)(0xd0, dst, src, stor);
     
    auto vaddsubps(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128)) => emit!(0, VEX, 128, DEFAULT, 0xf2)(0xd0, dst, src, stor);
    auto vaddsubps(RM)(YMM dst, YMM src, RM stor) if (valid!(RM, 256)) => emit!(0, VEX, 256, DEFAULT, 0xf2)(0xd0, dst, src, stor);

    auto vmovq(RM)(XMM dst, RM src) if (valid!(RM, 128, 64)) => emit!(0, VEX, 128, DEFAULT, 0xf3)(0x7e, dst, src);
    auto vmovq(Address!64 dst, XMM src) => emit!(0, VEX, 128, DEFAULT, 0x66)(0xd6, dst, src);

    auto vmovd(RM)(XMM dst, RM src) if (valid!(RM, 32)) => emit!(0, VEX, 128, DEFAULT, 0x66)(0x6e, dst, src);
    auto vmovd(RM)(RM dst, XMM src) if (valid!(RM, 32)) => emit!(0, VEX, 128, DEFAULT, 0x66)(0x7e, dst, src);

    auto vmovq(RM)(XMM dst, RM src) if (valid!(RM, 64)) => emit!(0, VEX, 128, DEFAULT, 0x66)(0x6e, dst, src);
    auto vmovq(RM)(RM dst, XMM src) if (valid!(RM, 64)) => emit!(0, VEX, 128, DEFAULT, 0x66)(0x7e, dst, src);

    /* ====== AES ====== */

    auto aesdec(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x38, 0xde, dst, src);
    auto vaesdec(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128)) => emit!(0, VEX, 128, F38, 0x66)(0xde, dst, src, stor);
    auto vaesdec(RM)(YMM dst, YMM src, RM stor) if (valid!(RM, 256)) => emit!(0, VEX, 256, F38, 0x66)(0xde, dst, src, stor);

    auto aesdec128kl(XMM dst, Address!384 src) => emit!(0, SSE)(0xf3, 0x0f, 0x38, 0xdd, dst, src);
    auto aesdec256kl(XMM dst, Address!512 src) => emit!(0, SSE)(0xf3, 0x0f, 0x38, 0xdf, dst, src);

    auto aesdeclast(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x38, 0xdf, dst, src);
    auto vaesdeclast(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128)) => emit!(0, VEX, 128, F38, 0x66)(0xdf, dst, src, stor);
    auto vaesdeclast(RM)(YMM dst, YMM src, RM stor) if (valid!(RM, 256)) => emit!(0, VEX, 256, F38, 0x66)(0xdf, dst, src, stor);

    auto aesdecwide128kl(Address!384 dst) => emit!(0, SSE)(0xf3, 0x0f, 0x38, 0xd8, dst, ecx);
    auto aesdecwide256kl(Address!512 dst) => emit!(0, SSE)(0xf3, 0x0f, 0x38, 0xd8, dst, ebx);

    auto aesenc(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x38, 0xdc, dst, src);
    auto vaesenc(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128)) => emit!(0, VEX, 128, F38, 0x66)(0xdc, dst, src, stor);
    auto vaesenc(RM)(YMM dst, YMM src, RM stor) if (valid!(RM, 256)) => emit!(0, VEX, 256, F38, 0x66)(0xdc, dst, src, stor);

    auto aesenc128kl(XMM dst, Address!384 src) => emit!(0, SSE)(0xf3, 0x0f, 0x38, 0xdc, dst, src);
    auto aesenc256kl(XMM dst, Address!512 src) => emit!(0, SSE)(0xf3, 0x0f, 0x38, 0xde, dst, src);

    auto aesenclast(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x38, 0xdd, dst, src);
    auto vaesenclast(RM)(XMM dst, XMM src, RM stor) if (valid!(RM, 128)) => emit!(0, VEX, 128, F38, 0x66)(0xdd, dst, src, stor);
    auto vaesenclast(RM)(YMM dst, YMM src, RM stor) if (valid!(RM, 256)) => emit!(0, VEX, 256, F38, 0x66)(0xdd, dst, src, stor);

    auto aesencwide128kl(Address!384 dst) => emit!(0, SSE)(0xf3, 0x0f, 0x38, 0xd8, dst, eax);
    auto aesencwide256kl(Address!512 dst) => emit!(0, SSE)(0xf3, 0x0f, 0x38, 0xd8, dst, edx);

    auto aesimc(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x38, 0xdb, dst, src);
    auto vaesimc(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, VEX, 128, F38, 0x66)(0xdb, dst, src);

    auto aeskeygenassist(RM)(XMM dst, RM src, ubyte imm8) if (valid!(RM, 128)) => emit!(0, SSE)(0x66, 0x0f, 0x3a, 0xdf, dst, src, imm8);
    auto vaeskeygenassist(RM)(XMM dst, RM src, ubyte imm8) if (valid!(RM, 128)) => emit!(0, VEX, 128, F3A, 0x66)(0xdf, dst, src, imm8);

    /* ====== SHA ====== */

    auto sha1msg1(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x38, 0xc9, dst, src);
    auto sha1msg2(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x38, 0xca, dst, src);
    auto sha1nexte(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x38, 0xc8, dst, src);

    auto sha256msg1(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x38, 0xcc, dst, src);

    auto sha1rnds4(RM)(XMM dst, RM src, ubyte imm8) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x3a, 0xcc, dst, src, imm8);

    auto sha256rnds2(RM)(XMM dst, RM src) if (valid!(RM, 128)) => emit!(0, SSE)(0x0f, 0x38, 0xcb, dst, src);

    /* ====== MAIN ====== */

    // NOTE: Branch hints are generally useless in the modern day, AMD CPUs don't even acknowledge them;
    // and thus these should not be used on any modern CPU.

    auto not_taken(size_t size)
    {
        // buffer = buffer[0..(buffer.length - size)]~0x2e~buffer[(buffer.length - size)..$];
        return size + 1;
    }

    auto taken(size_t size)
    {
        // buffer = buffer[0..(buffer.length - size)]~0x3e~buffer[(buffer.length - size)..$];
        return size + 1;
    }

    auto crc32(RM)(R32 dst, RM src) if (valid!(RM, 8)) => emit!0(0xf2, 0x0f, 0x38, 0xf0, dst, src);
    auto crc32(RM)(R32 dst, RM src) if (valid!(RM, 16)) => emit!0(0xf2, 0x0f, 0x38, 0xf1, dst, src);
    auto crc32(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0xf2, 0x0f, 0x38, 0xf1, dst, src);

    auto crc32(RM)(R64 dst, RM src) if (valid!(RM, 8)) => emit!0(0xf2, 0x0f, 0x38, 0xf0, dst, src);
    auto crc32(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0xf2, 0x0f, 0x38, 0xf1, dst, src);

    // literally 1984
    auto enqcmd(R32 dst, Address!512 src) => emit!0(0xf2, 0x0f, 0x38, 0xf8, dst, src);
    auto enqcmd(R64 dst, Address!512 src) => emit!0(0xf2, 0x0f, 0x38, 0xf8, dst, src);

    auto cmpxchg(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x0f, 0xb0, dst, src);
    auto cmpxchg(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x0f, 0xb1, dst, src);
    auto cmpxchg(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x0f, 0xb1, dst, src);
    auto cmpxchg(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x0f, 0xb1, dst, src);

    auto aaa() => emit!0(0x37);
    auto aad() => emit!0(0xd5, 0x0a);
    auto aad(ubyte imm8) => emit!0(0xd5, imm8);
    auto aam() => emit!0(0xd4, 0x0a);
    auto aam(ubyte imm8) => emit!0(0xd4, imm8);
    auto aas() => emit!0(0x3f);

    auto add(ubyte imm8) => emit!0(0x04, imm8);
    auto add(ushort imm16) => emit!0(0x05, imm16);
    auto add(uint imm32) => emit!0(0x05, imm32);
    auto add(ulong imm32) => emit!0(0x05, cast(long)imm32);

    auto add(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!0(0x80, dst, imm8);
    auto add(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!0(0x81, dst, imm16);
    auto add(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!0(0x81, dst, imm32);
    auto add(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!0(0x81, dst, imm32);
    auto add(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!0(0x83, dst, imm8);
    auto add(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!0(0x83, dst, imm8);
    auto add(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!0(0x83, dst, imm8);

    auto add(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x00, dst, src);
    auto add(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x01, dst, src);
    auto add(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x01, dst, src);
    auto add(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x01, dst, src);

    auto add(R8 src, Address!8 dst) => emit!0(0x02, dst, src);
    auto add(R16 src, Address!16 dst) => emit!0(0x03, dst, src);
    auto add(R32 src, Address!32 dst) => emit!0(0x03, dst, src);
    auto add(R64 src, Address!64 dst) => emit!0(0x03, dst, src);

    // auto add(R8 dst, Address!8 src) => emit!0(0x02, dst, src);
    // auto add(R16 dst, Address!16 src) => emit!0(0x03, dst, src);
    // auto add(R32 dst, Address!32 src) => emit!0(0x03, dst, src);
    // auto add(R64 dst, Address!64 src) => emit!0(0x03, dst, src);

    auto and(ubyte imm8) => emit!0(0x24, imm8);
    auto and(ushort imm16) => emit!0(0x25, imm16);
    auto and(uint imm32) => emit!0(0x25, imm32);
    auto and(ulong imm32) => emit!0(0x25, cast(long)imm32);

    auto and(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!4(0x80, dst, imm8);
    auto and(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!4(0x81, dst, imm16);
    auto and(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!4(0x81, dst, imm32);
    auto and(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!4(0x81, dst, imm32);
    auto and(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!4(0x83, dst, imm8);
    auto and(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!4(0x83, dst, imm8);
    auto and(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!4(0x83, dst, imm8);

    auto and(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x20, dst, src);
    auto and(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x21, dst, src);
    auto and(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x21, dst, src);
    auto and(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x21, dst, src);

    auto and(R8 dst, Address!8 src) => emit!0(0x22, dst, src);
    auto and(R16 dst, Address!16 src) => emit!0(0x23, dst, src);
    auto and(R32 dst, Address!32 src) => emit!0(0x23, dst, src);
    auto and(R64 dst, Address!64 src) => emit!0(0x23, dst, src);

    auto arpl(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x63, dst, src);

    auto bsf(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0xbc, src, dst);
    auto bsf(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0xbc, src, dst);
    auto bsf(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0xbc, src, dst);

    auto bsr(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0xbd, dst, src);
    auto bsr(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0xbd, dst, src);
    auto bsr(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0xbd, dst, src);

    auto bswap(R32 dst) => emit!(0, NRM)(0x0f, 0xc8, dst);
    auto bswap(R64 dst) => emit!(0, NRM)(0x0f, 0xc8, dst);

    auto bt(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x0f, 0xa3, dst, src); 
    auto bt(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x0f, 0xa3, dst, src); 
    auto bt(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x0f, 0xa3, dst, src); 
    auto bt(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!4(0x0f, 0xba, dst, imm8); 
    auto bt(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!4(0x0f, 0xba, dst, imm8); 
    auto bt(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!4(0x0f, 0xba, dst, imm8); 

    auto btc(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x0f, 0xbb, dst, src); 
    auto btc(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x0f, 0xbb, dst, src); 
    auto btc(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x0f, 0xbb, dst, src); 
    auto btc(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!7(0x0f, 0xba, dst, imm8); 
    auto btc(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!7(0x0f, 0xba, dst, imm8); 
    auto btc(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!7(0x0f, 0xba, dst, imm8); 

    auto btr(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x0f, 0xb3, dst, src); 
    auto btr(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x0f, 0xb3, dst, src); 
    auto btr(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x0f, 0xb3, dst, src); 
    auto btr(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!6(0x0f, 0xba, dst, imm8); 
    auto btr(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!6(0x0f, 0xba, dst, imm8); 
    auto btr(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!6(0x0f, 0xba, dst, imm8); 

    auto bts(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x0f, 0xab, dst, src); 
    auto bts(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x0f, 0xab, dst, src); 
    auto bts(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x0f, 0xab, dst, src); 
    auto bts(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!5(0x0f, 0xba, dst, imm8); 
    auto bts(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!5(0x0f, 0xba, dst, imm8); 
    auto bts(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!5(0x0f, 0xba, dst, imm8);

    auto cmp(ubyte imm8) => emit!0(0x3c, imm8);
    auto cmp(ushort imm16) => emit!0(0x3d, imm16);
    auto cmp(uint imm32) => emit!0(0x3d, imm32);
    auto cmp(ulong imm32) => emit!0(0x3d, cast(long)imm32);

    auto cmp(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!7(0x80, dst, imm8);
    auto cmp(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!7(0x81, dst, imm16);
    auto cmp(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!7(0x81, dst, imm32);
    auto cmp(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!7(0x81, dst, imm32);
    auto cmp(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!7(0x83, dst, imm8); 
    auto cmp(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!7(0x83, dst, imm8); 
    auto cmp(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!7(0x83, dst, imm8); 

    auto cmp(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x38, dst, src);
    auto cmp(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x39, dst, src);
    auto cmp(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x39, dst, src);
    auto cmp(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x39, dst, src);

    auto cmp(R8 dst, Address!8 src) => emit!0(0x3a, dst, src);
    auto cmp(R16 dst, Address!16 src) => emit!0(0x3b, dst, src);
    auto cmp(R32 dst, Address!32 src) => emit!0(0x3b, dst, src);
    auto cmp(R64 dst, Address!64 src) => emit!0(0x3b, dst, src);

    auto cwd() => emit!0(0x66, 0x99);
    auto cdq() => emit!0(0x99);
    auto cqo() => emit!0(0x48, 0x99);

    auto cbw() => emit!0(0x66, 0x98);
    auto cwde() => emit!0(0x98);
    auto cdqe() => emit!0(0x48, 0x98);

    auto cpuid() => emit!0(0x0f, 0xa2);
    auto cpuid(uint imm32) => mov(eax, imm32) + cpuid();

    auto clc() => emit!0(0xf8);
    auto cld() => emit!0(0xfc);
    auto cli() => emit!0(0xfa);
    auto clts() => emit!0(0x0f, 0x06);

    auto cmc() => emit!0(0xf5);

    auto dec(RM)(RM dst) if (valid!(RM, 8)) => emit!1(0xfe, dst);
    static if (X64)
    auto dec(RM)(RM dst) if (valid!(RM, 16)) => emit!1(0xff, dst);
    static if (!X64)
    auto dec(Address!16 dst) => emit!1(0xff, dst);
    static if (X64)
    auto dec(RM)(RM dst) if (valid!(RM, 32)) => emit!1(0xff, dst);
    static if (!X64)
    auto dec(Address!32 dst) => emit!1(0xff, dst);
    auto dec(RM)(RM dst) if (valid!(RM, 64)) => emit!1(0xff, dst);

    static if (!X64)
    auto dec(R16 dst) => emit!(0, NRM)(0x48, dst);
    static if (!X64)
    auto dec(R32 dst) => emit!(0, NRM)(0x48, dst);

    auto int3() => emit!0(0xcc);
    auto _int(ubyte imm8) => emit!0(0xcd, imm8);
    auto into() => emit!0(0xce);
    auto int1() => emit!0(0xf1);
    auto ud0(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0xff, dst, src);
    auto ud1(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0xb9, dst, src);
    auto ud2() => emit!0(0x0f, 0x0b);
    
    auto iret() => emit!0(0xcf);
    auto iretd() => emit!0(0xcf);
    auto iretq() => emit!0(0xcf);

    auto inc(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0xfe, dst);
    static if (X64)
    auto inc(RM)(RM dst) if (valid!(RM, 16)) => emit!0(0xff, dst);
    static if (!X64)
    auto inc(Address!16 dst) => emit!0(0xff, dst);
    static if (X64)
    auto inc(RM)(RM dst) if (valid!(RM, 32)) => emit!0(0xff, dst);
    static if (!X64)
    auto inc(Address!32 dst) => emit!0(0xff, dst);
    auto inc(RM)(RM dst) if (valid!(RM, 64)) => emit!0(0xff, dst);

    static if (!X64)
    auto inc(R16 dst) => emit!(0, NRM)(0x40, dst);
    static if (!X64)
    auto inc(R32 dst) => emit!(0, NRM)(0x40, dst);

    auto hlt() => emit!0(0xf4);
    auto pause() => emit!0(0xf3, 0x90);
    auto swapgs() => emit!0(0x0f, 0x01, 0xf8);
    
    auto lock(size_t size)
    {
        // buffer = buffer[0..(buffer.length - size)]~0xf0~buffer[(buffer.length - size)..$];
        // return size + 1;
    }

    auto wait() => emit!0(0x9b);
    auto fwait() => emit!0(0x9b);

    auto sysretc() => emit!0(0x0f, 0x07);
    auto sysret() => emit!0(0x0f, 0x07);
    auto syscall() => emit!0(0x0f, 0x05);
    auto rsm() => emit!0(0x0f, 0xaa);

    auto leave() => emit!0(0xc9);
    auto enter(ushort imm16) => emit!0(0xc8, imm16, 0x00);
    auto enter(ushort imm16, ubyte imm8) => emit!0(0xc8, imm16, imm8);
    
    auto lea(R16 dst, Address!16 src) => emit!0(0x8d, dst, src);
    auto lea(R32 dst, Address!32 src) => emit!0(0x8d, dst, src);
    auto lea(R64 dst, Address!64 src) => emit!0(0x8d, dst, src);

    auto lds(RM)(R16 dst, Address!16) => emit!0(0xc5, dst, src);
    auto lds(RM)(R32 dst, Address!32) => emit!0(0xc5, dst, src);

    auto lss(RM)(R16 dst, Address!16) => emit!0(0x0f, 0xb2, dst, src);
    auto lss(RM)(R32 dst, Address!32) => emit!0(0x0f, 0xb2, dst, src);
    auto lss(RM)(R64 dst, Address!64) => emit!0(0x0f, 0xb2, dst, src);

    auto les(RM)(R16 dst, Address!16) => emit!0(0xc4, dst, src);
    auto les(RM)(R32 dst, Address!32) => emit!0(0xc4, dst, src);

    auto lfs(RM)(R16 dst, Address!16) => emit!0(0x0f, 0xb4, dst, src);
    auto lfs(RM)(R32 dst, Address!32) => emit!0(0x0f, 0xb4, dst, src);
    auto lfs(RM)(R64 dst, Address!64) => emit!0(0x0f, 0xb4, dst, src);

    auto lgs(RM)(R16 dst, Address!16) => emit!0(0x0f, 0xb5, dst, src);
    auto lgs(RM)(R32 dst, Address!32) => emit!0(0x0f, 0xb5, dst, src);
    auto lgs(RM)(R64 dst, Address!64) => emit!0(0x0f, 0xb5, dst, src);

    auto lsl(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0x03, dst, src);
    auto lsl(R32 dst, R32 src) => emit!0(0x0f, 0x03, dst, src);
    auto lsl(R64 dst, R32 src) => emit!0(0x0f, 0x03, dst, src);
    auto lsl(R32 dst, Address!16 src) => emit!0(0x0f, 0x03, dst, src);
    auto lsl(R64 dst, Address!16 src) => emit!0(0x0f, 0x03, dst, src);

    auto ltr(RM)(RM dst) if (valid!(RM, 16)) => emit!3(0x0f, 0x00, dst);
    auto str(RM)(RM dst) if (valid!(RM, 16)) => emit!1(0x0f, 0x00, dst);

    auto neg(RM)(RM dst) if (valid!(RM, 8)) => emit!3(0xf6, dst);
    auto neg(RM)(RM dst) if (valid!(RM, 16)) => emit!3(0xf7, dst);
    auto neg(RM)(RM dst) if (valid!(RM, 32)) => emit!3(0xf7, dst);
    auto neg(RM)(RM dst) if (valid!(RM, 64)) => emit!3(0xf7, dst);

    auto nop() => emit!0(0x90);
    auto nop(RM)(RM dst) if (valid!(RM, 16)) => emit!0(0x0f, 0x1f, dst);
    auto nop(RM)(RM dst) if (valid!(RM, 16)) => emit!0(0x0f, 0x1f, dst);

    auto not(RM)(RM dst) if (valid!(RM, 8)) => emit!2(0xf6, dst);
    auto not(RM)(RM dst) if (valid!(RM, 16)) => emit!2(0xf7, dst);
    auto not(RM)(RM dst) if (valid!(RM, 32)) => emit!2(0xf7, dst);
    auto not(RM)(RM dst) if (valid!(RM, 64)) => emit!2(0xf7, dst);

    auto ret() => emit!0(0xc3);
    auto ret(ushort imm16) => emit!0(0xc2, imm16);
    auto retf() => emit!0(0xcb);
    auto retf(ushort imm16) => emit!0(0xca, imm16);

    auto stc() => emit!0(0xf9);
    auto std() => emit!0(0xfd);
    auto sti() => emit!0(0xfb);

    auto sub(ubyte imm8) => emit!0(0x2c, imm8);
    auto sub(ushort imm16) => emit!0(0x2d, imm16);
    auto sub(uint imm32) => emit!0(0x2d, imm32);
    auto sub(ulong imm32) => emit!0(0x2d, cast(long)imm32);

    auto sub(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!5(0x80, dst, imm8);
    auto sub(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!5(0x81, dst, imm16);
    auto sub(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!5(0x81, dst, imm32);
    auto sub(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!5(0x81, dst, imm32);
    auto sub(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!5(0x83, dst, imm8);
    auto sub(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!5(0x83, dst, imm8);
    auto sub(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!5(0x83, dst, imm8);

    auto sub(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x28, dst, src);
    auto sub(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x29, dst, src);
    auto sub(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x29, dst, src);
    auto sub(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x29, dst, src);

    auto sub(R8 dst, Address!8 src) => emit!0(0x2a, dst, src);
    auto sub(R16 dst, Address!16 src) => emit!0(0x2b, dst, src);
    auto sub(R32 dst, Address!32 src) => emit!0(0x2b, dst, src);
    auto sub(R64 dst, Address!64 src) => emit!0(0x2b, dst, src);

    auto sbb(ubyte imm8) => emit!0(0x1c, imm8);
    auto sbb(ushort imm16) => emit!0(0x1d, imm16);
    auto sbb(uint imm32) => emit!0(0x1d, imm32);
    auto sbb(ulong imm32) => emit!0(0x1d, cast(long)imm32);

    auto sbb(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!3(0x80, dst, imm8);
    auto sbb(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!3(0x81, dst, imm16);
    auto sbb(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!3(0x81, dst, imm32);
    auto sbb(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!3(0x81, dst, imm32);
    auto sbb(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!3(0x83, dst, imm8);
    auto sbb(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!3(0x83, dst, imm8);
    auto sbb(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!3(0x83, dst, imm8);

    auto sbb(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x18, dst, src);
    auto sbb(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x19, dst, src);
    auto sbb(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x19, dst, src);
    auto sbb(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x19, dst, src);

    auto sbb(R8 dst, Address!8 src) => emit!0(0x1a, dst, src);
    auto sbb(R16 dst, Address!16 src) => emit!0(0x1b, dst, src);
    auto sbb(R32 dst, Address!32 src) => emit!0(0x1b, dst, src);
    auto sbb(R64 dst, Address!64 src) => emit!0(0x1b, dst, src);

    auto xor(ubyte imm8) => emit!0(0x34, imm8);
    auto xor(ushort imm16) => emit!0(0x35, imm16);
    auto xor(uint imm32) => emit!0(0x35, imm32);
    auto xor(ulong imm32) => emit!0(0x35, cast(long)imm32);

    auto xor(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!6(0x80, dst, imm8);
    auto xor(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!6(0x81, dst, imm16);
    auto xor(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!6(0x81, dst, imm32);
    auto xor(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!6(0x81, dst, imm32);
    auto xor(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!6(0x83, dst, imm8);
    auto xor(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!6(0x83, dst, imm8);
    auto xor(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!6(0x83, dst, imm8);

    auto xor(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x30, dst, src);
    auto xor(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x31, dst, src);
    auto xor(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x31, dst, src);
    auto xor(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x31, dst, src);

    auto xor(R8 dst, Address!8 src) => emit!0(0x32, dst, src);
    auto xor(R16 dst, Address!16 src) => emit!0(0x33, dst, src);
    auto xor(R32 dst, Address!32 src) => emit!0(0x33, dst, src);
    auto xor(R64 dst, Address!64 src) => emit!0(0x33, dst, src);

    auto or(ubyte imm8) => emit!0(0x0c, imm8);
    auto or(ushort imm16) => emit!0(0x0d, imm16);
    auto or(uint imm32) => emit!0(0x0d, imm32);
    auto or(ulong imm32) => emit!0(0x0d, cast(long)imm32);

    auto or(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!1(0x80, dst, imm8);
    auto or(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!1(0x81, dst, imm16);
    auto or(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!1(0x81, dst, imm32);
    auto or(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!1(0x81, dst, imm32);
    auto or(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => emit!1(0x83, dst, imm8);
    auto or(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => emit!1(0x83, dst, imm8);
    auto or(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => emit!1(0x83, dst, imm8);

    auto or(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x8, dst, src);
    auto or(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x9, dst, src);
    auto or(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x9, dst, src);
    auto or(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x9, dst, src);

    auto or(R8 dst, Address!8 src) => emit!0(0xa, dst, src);
    auto or(R16 dst, Address!16 src) => emit!0(0xb, dst, src);
    auto or(R32 dst, Address!32 src) => emit!0(0xb, dst, src);
    auto or(R64 dst, Address!64 src) => emit!0(0xb, dst, src);

    auto sal(RM)(RM dst) if (valid!(RM, 8)) => emit!4(0xd2, dst);
    auto sal(RM)(RM dst, ubyte imm8) if (valid!(RM, 8))
    {
        if (imm8 == 1)
            return emit!4(0xd0, dst);
        else
            return emit!4(0xc0, dst, imm8);
    }
    auto sal(RM)(RM dst) if (valid!(RM, 16)) => emit!4(0xd3, dst);
    auto sal(RM)(RM dst, ubyte imm8) if (valid!(RM, 16))
    {
        if (imm8 == 1)
            return emit!4(0xd1, dst);
        else
            return emit!4(0xc1, dst, imm8);
    }
    auto sal(RM)(RM dst) if (valid!(RM, 32)) => emit!4(0xd3, dst);
    auto sal(RM)(RM dst, ubyte imm8) if (valid!(RM, 32))
    {
        if (imm8 == 1)
            return emit!4(0xd1, dst);
        else
            return emit!4(0xc1, dst, imm8);
    }
    auto sal(RM)(RM dst) if (valid!(RM, 64)) => emit!4(0xd3, dst);
    auto sal(RM)(RM dst, ubyte imm8) if (valid!(RM, 64))
    {
        if (imm8 == 1)
            return emit!4(0xd1, dst);
        else
            return emit!4(0xc1, dst, imm8);
    }

    auto sar(RM)(RM dst) if (valid!(RM, 8)) => emit!7(0xd2, dst);
    auto sar(RM)(RM dst, ubyte imm8) if (valid!(RM, 8))
    {
        if (imm8 == 1)
            return emit!7(0xd0, dst);
        else
            return emit!7(0xc0, dst, imm8);
    }
    auto sar(RM)(RM dst) if (valid!(RM, 16)) => emit!7(0xd3, dst);
    auto sar(RM)(RM dst, ubyte imm8) if (valid!(RM, 16))
    {
        if (imm8 == 1)
            return emit!7(0xd1, dst);
        else
            return emit!7(0xc1, dst, imm8);
    }
    auto sar(RM)(RM dst) if (valid!(RM, 32)) => emit!7(0xd3, dst);
    auto sar(RM)(RM dst, ubyte imm8) if (valid!(RM, 32))
    {
        if (imm8 == 1)
            return emit!7(0xd1, dst);
        else
            return emit!7(0xc1, dst, imm8);
    }
    auto sar(RM)(RM dst) if (valid!(RM, 64)) => emit!7(0xd3, dst);
    auto sar(RM)(RM dst, ubyte imm8) if (valid!(RM, 64))
    {
        if (imm8 == 1)
            return emit!7(0xd1, dst);
        else
            return emit!7(0xc1, dst, imm8);
    }

    auto shl(RM)(RM dst) if (valid!(RM, 8)) => sal(dst);
    auto shl(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => sal(dst, imm8);
    auto shl(RM)(RM dst) if (valid!(RM, 16)) => sal(dst);
    auto shl(RM)(RM dst, ubyte imm8) if (valid!(RM, 16)) => sal(dst, imm8);
    auto shl(RM)(RM dst) if (valid!(RM, 32)) => sal(dst);
    auto shl(RM)(RM dst, ubyte imm8) if (valid!(RM, 32)) => sal(dst, imm8);
    auto shl(RM)(RM dst) if (valid!(RM, 64)) => sal(dst);
    auto shl(RM)(RM dst, ubyte imm8) if (valid!(RM, 64)) => sal(dst, imm8);

    auto shr(RM)(RM dst) if (valid!(RM, 8)) => emit!5(0xd2, dst);
    auto shr(RM)(RM dst, ubyte imm8) if (valid!(RM, 8))
    {
        if (imm8 == 1)
            return emit!5(0xd0, dst);
        else
            return emit!5(0xc0, dst, imm8);
    }
    auto shr(RM)(RM dst) if (valid!(RM, 16)) => emit!5(0xd3, dst);
    auto shr(RM)(RM dst, ubyte imm8) if (valid!(RM, 16))
    {
        if (imm8 == 1)
            return emit!5(0xd1, dst);
        else
            return emit!5(0xc1, dst, imm8);
    }
    auto shr(RM)(RM dst) if (valid!(RM, 32)) => emit!5(0xd3, dst);
    auto shr(RM)(RM dst, ubyte imm8) if (valid!(RM, 32))
    {
        if (imm8 == 1)
            return emit!5(0xd1, dst);
        else
            return emit!5(0xc1, dst, imm8);
    }
    auto shr(RM)(RM dst) if (valid!(RM, 64)) => emit!5(0xd3, dst);
    auto shr(RM)(RM dst, ubyte imm8) if (valid!(RM, 64))
    {
        if (imm8 == 1)
            return emit!5(0xd1, dst);
        else
            return emit!5(0xc1, dst, imm8);
    }

    auto rcl(RM)(RM dst) if (valid!(RM, 8)) => emit!2(0xd2, dst);
    auto rcl(RM)(RM dst, ubyte imm8) if (valid!(RM, 8))
    {
        if (imm8 == 1)
            return emit!2(0xd0, dst);
        else
            return emit!2(0xc0, dst, imm8);
    }
    auto rcl(RM)(RM dst) if (valid!(RM, 16)) => emit!2(0xd3, dst);
    auto rcl(RM)(RM dst, ubyte imm8) if (valid!(RM, 16))
    {
        if (imm8 == 1)
            return emit!2(0xd1, dst);
        else
            return emit!2(0xc1, dst, imm8);
    }
    auto rcl(RM)(RM dst) if (valid!(RM, 32)) => emit!2(0xd3, dst);
    auto rcl(RM)(RM dst, ubyte imm8) if (valid!(RM, 32))
    {
        if (imm8 == 1)
            return emit!2(0xd1, dst);
        else
            return emit!2(0xc1, dst, imm8);
    }
    auto rcl(RM)(RM dst) if (valid!(RM, 64)) => emit!2(0xd3, dst);
    auto rcl(RM)(RM dst, ubyte imm8) if (valid!(RM, 64))
    {
        if (imm8 == 1)
            return emit!2(0xd1, dst);
        else
            return emit!2(0xc1, dst, imm8);
    }

    auto rcr(RM)(RM dst) if (valid!(RM, 8)) => emit!3(0xd2, dst);
    auto rcr(RM)(RM dst, ubyte imm8) if (valid!(RM, 8))
    {
        if (imm8 == 1)
            return emit!3(0xd0, dst);
        else
            return emit!3(0xc0, dst, imm8);
    }
    auto rcr(RM)(RM dst) if (valid!(RM, 16)) => emit!3(0xd3, dst);
    auto rcr(RM)(RM dst, ubyte imm8) if (valid!(RM, 16))
    {
        if (imm8 == 1)
            return emit!3(0xd1, dst);
        else
            return emit!3(0xc1, dst, imm8);
    }
    auto rcr(RM)(RM dst) if (valid!(RM, 32)) => emit!3(0xd3, dst);
    auto rcr(RM)(RM dst, ubyte imm8) if (valid!(RM, 32))
    {
        if (imm8 == 1)
            return emit!3(0xd1, dst);
        else
            return emit!3(0xc1, dst, imm8);
    }
    auto rcr(RM)(RM dst) if (valid!(RM, 64)) => emit!3(0xd3, dst);
    auto rcr(RM)(RM dst, ubyte imm8) if (valid!(RM, 64))
    {
        if (imm8 == 1)
            return emit!3(0xd1, dst);
        else
            return emit!3(0xc1, dst, imm8);
    }

    auto rol(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0xd2, dst);
    auto rol(RM)(RM dst, ubyte imm8) if (valid!(RM, 8))
    {
        if (imm8 == 1)
            return emit!0(0xd0, dst);
        else
            return emit!0(0xc0, dst, imm8);
    }
    auto rol(RM)(RM dst) if (valid!(RM, 16)) => emit!0(0xd3, dst);
    auto rol(RM)(RM dst, ubyte imm8) if (valid!(RM, 16))
    {
        if (imm8 == 1)
            return emit!0(0xd1, dst);
        else
            return emit!0(0xc1, dst, imm8);
    }
    auto rol(RM)(RM dst) if (valid!(RM, 32)) => emit!0(0xd3, dst);
    auto rol(RM)(RM dst, ubyte imm8) if (valid!(RM, 32))
    {
        if (imm8 == 1)
            return emit!0(0xd1, dst);
        else
            return emit!0(0xc1, dst, imm8);
    }
    auto rol(RM)(RM dst) if (valid!(RM, 64)) => emit!0(0xd3, dst);
    auto rol(RM)(RM dst, ubyte imm8) if (valid!(RM, 64))
    {
        if (imm8 == 1)
            return emit!0(0xd1, dst);
        else
            return emit!0(0xc1, dst, imm8);
    }

    auto ror(RM)(RM dst) if (valid!(RM, 8)) => emit!1(0xd2, dst);
    auto ror(RM)(RM dst, ubyte imm8) if (valid!(RM, 8))
    {
        if (imm8 == 1)
            return emit!1(0xd0, dst);
        else
            return emit!1(0xc0, dst, imm8);
    }
    auto ror(RM)(RM dst) if (valid!(RM, 16)) => emit!1(0xd3, dst);
    auto ror(RM)(RM dst, ubyte imm8) if (valid!(RM, 16))
    {
        if (imm8 == 1)
            return emit!1(0xd1, dst);
        else
            return emit!1(0xc1, dst, imm8);
    }
    auto ror(RM)(RM dst) if (valid!(RM, 32)) => emit!1(0xd3, dst);
    auto ror(RM)(RM dst, ubyte imm8) if (valid!(RM, 32))
    {
        if (imm8 == 1)
            return emit!1(0xd1, dst);
        else
            return emit!1(0xc1, dst, imm8);
    }
    auto ror(RM)(RM dst) if (valid!(RM, 64)) => emit!1(0xd3, dst);
    auto ror(RM)(RM dst, ubyte imm8) if (valid!(RM, 64))
    {
        if (imm8 == 1)
            return emit!1(0xd1, dst);
        else
            return emit!1(0xc1, dst, imm8);
    }

    auto verr(RM)(RM dst) if (valid!(RM, 16)) => emit!4(0xf0, 0x00, dst);
    auto verw(RM)(RM dst) if (valid!(RM, 16)) => emit!5(0xf0, 0x00, dst);

    auto test(ubyte imm8) => emit!0(0xa8, imm8);
    auto test(ushort imm16) => emit!0(0xa9, imm16);
    auto test(uint imm32) => emit!0(0xa9, imm32);
    auto test(ulong imm32) => emit!0(0xa9, cast(long)imm32);

    auto test(RM)(RM dst, ubyte imm8) if (valid!(RM, 8)) => emit!0(0xf6, dst, imm8);
    auto test(RM)(RM dst, ushort imm16) if (valid!(RM, 16)) => emit!0(0xf7, dst, imm16);
    auto test(RM)(RM dst, uint imm32) if (valid!(RM, 32)) => emit!0(0xf7, dst, imm32);
    auto test(RM)(RM dst, uint imm32) if (valid!(RM, 64)) => emit!0(0xf7, dst, cast(long)imm32);

    auto test(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x84, dst, src);
    auto test(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x85, dst, src);
    auto test(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x85, dst, src);
    auto test(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x85, dst, src);

    auto pop(Address!16 dst) => emit!0(0x8f, dst);
    static if (!X64)
    auto pop(Address!32 dst) => emit!(0, NP)(0x8f, dst);
    static if (X64)
    auto pop(Address!64 dst) => emit!(0, NP)(0x8f, dst);

    auto pop(R16 dst) => emit!(0, NRM)(0x58, dst);
    static if (!X64)
    auto pop(R32 dst) => emit!(0, NRM)(0x58, dst);
    static if (X64)
    auto pop(R64 dst) => emit!(0, NRM)(0x58, dst);

    auto popds() => emit!0(0x1f);
    auto popes() => emit!0(0x07);
    auto popss() => emit!0(0x17);
    auto popfs() => emit!0(0x0f, 0xa1);
    auto popgs() => emit!0(0x0f, 0xa9); 

    auto popa() => emit!0(0x61);
    auto popad() => emit!0(0x61);

    auto popf() => emit!0(0x9d);
    auto popfd() => emit!0(0x9d);
    auto popfq() => emit!0(0x9d);

    auto push(Address!16 dst) => emit!6(0xff, dst);
    static if (!X64)
    auto push(Address!32 dst) => emit!(6, NP)(0xff, dst);
    static if (X64)
    auto push(Address!64 dst) => emit!(6, NP)(0xff, dst);

    auto push(R16 dst) => emit!(0, NRM)(0x50, dst);
    static if (!X64)
    auto push(R32 dst) => emit!(0, NRM)(0x50, dst);
    static if (X64)
    auto push(R64 dst) => emit!(0, NRM)(0x50, dst);

    auto push(ubyte imm8) => emit!0(0x6a, imm8);
    auto push(ushort imm16) => emit!0(0x68, imm16);
    auto push(uint imm32) => emit!0(0x68, imm32);

    auto pushcs() => emit!0(0x0e);
    auto pushss() => emit!0(0x16);
    auto pushds() => emit!0(0x1e);
    auto pushes() => emit!0(0x06);
    auto pushfs() => emit!0(0x0f, 0xa0);
    auto pushgs() => emit!0(0x0f, 0xa8); 

    auto pusha() => emit!0(0x60);
    auto pushad() => emit!0(0x60);

    auto pushf() => emit!0(0x9c);
    auto pushfd() => emit!0(0x9c);
    auto pushfq() => emit!0(0x9c);

    auto xadd(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x0f, 0xc0, dst, src);
    auto xadd(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x0f, 0xc1, dst, src);
    auto xadd(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x0f, 0xc1, dst, src);
    auto xadd(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x0f, 0xc1, dst, src);

    auto xchg(R16 dst) => emit!(0, NRM)(90, dst);
    auto xchg(R32 dst) => emit!(0, NRM)(90, dst);
    auto xchg(R64 dst) => emit!(0, NRM)(90, dst);

    auto xchg(A, B)(A dst, B src) if (valid!(A, 8) && valid!(B, 8)) => emit!0(0x86, dst, src);
    auto xchg(A, B)(A dst, B src) if (valid!(A, 16) && valid!(B, 16)) => emit!0(0x87, dst, src);
    auto xchg(A, B)(A dst, B src) if (valid!(A, 32) && valid!(B, 32)) => emit!0(0x87, dst, src);
    auto xchg(A, B)(A dst, B src) if (valid!(A, 64) && valid!(B, 64)) => emit!0(0x87, dst, src);

    auto xlat() => emit!0(0xd7);
    static if (!X64)
    auto xlatb() => emit!0(0xd7);
    static if (X64)
    auto xlatb() => emit!0(0x48, 0xd7);

    auto lar(R16 dst, Address!16 src) => emit!0(0x0f, 0x02, dst, src);
    auto lar(R16 dst, R16 src) => emit!0(0x0f, 0x02, dst, src);
    auto lar(R32 dst, Address!16 src) => emit!0(0x0f, 0x02, dst, src);
    auto lar(R32 dst, R32 src) => emit!0(0x0f, 0x02, dst, src);

    auto daa() => emit!0(0x27);
    auto das() => emit!0(0x2f);

    auto mul(RM)(RM dst) if (valid!(RM, 8)) => emit!4(0xf6, dst);
    auto mul(RM)(RM dst) if (valid!(RM, 16)) => emit!4(0xf7, dst);
    auto mul(RM)(RM dst) if (valid!(RM, 32)) => emit!4(0xf7, dst);
    auto mul(RM)(RM dst) if (valid!(RM, 64)) => emit!4(0xf7, dst);

    auto imul(RM)(RM dst) if (valid!(RM, 8)) => emit!5(0xf6, dst);
    auto imul(RM)(RM dst) if (valid!(RM, 16)) => emit!5(0xf7, dst);
    auto imul(RM)(RM dst) if (valid!(RM, 32)) => emit!5(0xf7, dst);
    auto imul(RM)(RM dst) if (valid!(RM, 64)) => emit!5(0xf7, dst);

    auto imul(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0xaf, src, dst);
    auto imul(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x0f, 0xaf, src, dst);
    auto imul(RM)(R64 dst, RM src) if (valid!(RM, 64)) => emit!0(0x0f, 0xaf, src, dst);

    auto imul(RM)(R16 dst, RM src, ubyte imm8) if (valid!(RM, 16)) => emit!0(0x6b, dst, src, imm8);
    auto imul(RM)(R32 dst, RM src, ubyte imm8) if (valid!(RM, 32)) => emit!0(0x6b, dst, src, imm8);
    auto imul(RM)(R64 dst, RM src, ubyte imm8) if (valid!(RM, 64)) => emit!0(0x6b, dst, src, imm8);
    auto imul(RM)(R16 dst, RM src, ushort imm16) if (valid!(RM, 16)) => emit!0(0x69, dst, src, imm16);
    auto imul(RM)(R32 dst, RM src, uint imm32) if (valid!(RM, 32)) => emit!0(0x69, dst, src, imm32);
    auto imul(RM)(R64 dst, RM src, uint imm32) if (valid!(RM, 64)) => emit!0(0x69, dst, src, imm32);

    auto div(RM)(RM dst) if (valid!(RM, 8)) => emit!6(0xf6, dst);
    auto div(RM)(RM dst) if (valid!(RM, 16)) => emit!6(0xf7, dst);
    auto div(RM)(RM dst) if (valid!(RM, 32)) => emit!6(0xf7, dst);
    auto div(RM)(RM dst) if (valid!(RM, 64)) => emit!6(0xf7, dst);

    auto idiv(RM)(RM dst) if (valid!(RM, 8)) => emit!7(0xf6, dst);
    auto idiv(RM)(RM dst) if (valid!(RM, 16)) => emit!7(0xf7, dst);
    auto idiv(RM)(RM dst) if (valid!(RM, 32)) => emit!7(0xf7, dst);
    auto idiv(RM)(RM dst) if (valid!(RM, 64)) => emit!7(0xf7, dst);

    auto mov(RM)(RM dst, R8 src) if (valid!(RM, 8)) => emit!0(0x88, dst, src);
    auto mov(RM)(RM dst, R16 src) if (valid!(RM, 16)) => emit!0(0x89, dst, src);
    auto mov(RM)(RM dst, R32 src) if (valid!(RM, 32)) => emit!0(0x89, dst, src);
    auto mov(RM)(RM dst, R64 src) if (valid!(RM, 64)) => emit!0(0x89, dst, src);

    auto mov(R8 dst, Address!8 src) => emit!0(0x8a, dst, src);
    auto mov(R16 dst, Address!16 src) => emit!0(0x8b, dst, src);
    auto mov(R32 dst, Address!32 src) => emit!0(0x8b, dst, src);
    auto mov(R64 dst, Address!64 src) => emit!0(0x8b, dst, src);
    
    auto mov(R8 dst, ubyte imm8) => emit!(0, NRM)(0xb0, dst, imm8);
    auto mov(R16 dst, ushort imm16) => emit!(0, NRM)(0xb8, dst, imm16);
    auto mov(R32 dst, uint imm32) => emit!(0, NRM)(0xb8, dst, imm32);
    auto mov(R64 dst, ulong imm64) => emit!(0, NRM)(0xb8, dst, imm64);

    auto mov(Address!8 dst, ubyte imm8) => emit!0(0xc6, dst, imm8);
    auto mov(Address!16 dst, ushort imm16) => emit!0(0xc7, dst, imm16);
    auto mov(Address!32 dst, uint imm32) => emit!0(0xc7, dst, imm32);
    auto mov(Address!64 dst, uint imm32) => emit!0(0xc7, dst, imm32);

    auto mov(R32 dst, CR src) => emit!0(0x0f, 0x20, dst, src);
    auto mov(R64 dst, CR src) => emit!0(0x0f, 0x20, dst, src);
    auto mov(CR dst, R32 src) => emit!0(0x0f, 0x22, dst, src);
    auto mov(CR dst, R64 src) => emit!0(0x0f, 0x22, dst, src);

    auto mov(R32 dst, DR src) => emit!0(0x0f, 0x21, dst, src);
    auto mov(R64 dst, DR src) => emit!0(0x0f, 0x21, dst, src);
    auto mov(DR dst, R32 src) => emit!0(0x0f, 0x23, dst, src);
    auto mov(DR dst, R64 src) => emit!0(0x0f, 0x23, dst, src);

    auto movsx(RM)(R16 dst, RM src) if (valid!(RM, 8)) => emit!0(0x0f, 0xbe, src, dst);
    auto movsx(RM)(R32 dst, RM src) if (valid!(RM, 8)) => emit!0(0x0f, 0xbe, src, dst);
    auto movsx(RM)(R64 dst, RM src) if (valid!(RM, 8)) => emit!0(0x0f, 0xbe, src, dst);

    auto movsx(RM)(R32 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0xbf, src, dst);
    auto movsx(RM)(R64 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0xbf, src, dst);

    auto movsxd(RM)(R16 dst, RM src) if (valid!(RM, 16)) => emit!0(0x63, src, dst);
    auto movsxd(RM)(R32 dst, RM src) if (valid!(RM, 32)) => emit!0(0x63, src, dst);
    auto movsxd(RM)(R64 dst, RM src) if (valid!(RM, 32)) => emit!0(0x63, src, dst);

    auto movzx(RM)(R16 dst, RM src) if (valid!(RM, 8)) => emit!0(0x0f, 0xb6, src, dst);
    auto movzx(RM)(R32 dst, RM src) if (valid!(RM, 8)) => emit!0(0x0f, 0xb6, src, dst);
    auto movzx(RM)(R64 dst, RM src) if (valid!(RM, 8)) => emit!0(0x0f, 0xb6, src, dst);

    auto movzx(RM)(R32 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0xb7, src, dst);
    auto movzx(RM)(R64 dst, RM src) if (valid!(RM, 16)) => emit!0(0x0f, 0xb7, src, dst);

    auto call(ushort rel16) => emit!0(0xe8, rel16);
    auto call(uint rel32) => emit!0(0xe8, rel32);

    auto call(R16 dst) => emit!2(0xff, dst);
    auto call(R32 dst) => emit!2(0xff, dst);
    auto call(R64 dst) => emit!2(0xff, dst);

    auto call(Address!16 dst) => emit!3(0xff, dst);
    auto call(Address!32 dst) => emit!3(0xff, dst);
    auto call(Address!64 dst) => emit!3(0xff, dst);

    auto loop(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "loop", name !in labels);
    auto loope(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "loope", name !in labels);
    auto loopne(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "loopne", name !in labels);

    auto jmp(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jmp", name !in labels);
    auto jmp(RM)(RM dst) if (valid!(RM, 16)) => emit!4(0xff, dst);
    auto jmp(RM)(RM dst) if (valid!(RM, 32)) => emit!4(0xff, dst);
    auto jmp(RM)(RM dst) if (valid!(RM, 64)) => emit!4(0xff, dst);

    auto jmp(Address!16 dst) => emit!5(0xff, dst);
    auto jmp(Address!32 dst) => emit!5(0xff, dst);
    auto jmp(Address!64 dst) => emit!5(0xff, dst);

    auto jmp(ushort imm16) => emit!0(0xea, imm16);
    auto jmp(uint imm32) => emit!0(0xea, imm32);
    auto jmp(ulong imm64) => emit!0(0xea, cast(long)imm64);

    auto ja(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "ja", name !in labels);
    auto jae(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jae", name !in labels);
    auto jb(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jb", name !in labels);
    auto jbe(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jbe", name !in labels);
    auto jc(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jc", name !in labels);
    auto jcxz(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jcxz", name !in labels);
    auto jecxz(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jecxz", name !in labels);
    auto jrcxz(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jrcxz", name !in labels);
    auto je(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "je", name !in labels);
    auto jg(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jg", name !in labels);
    auto jge(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jge", name !in labels);
    auto jl(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jl", name !in labels);
    auto jle(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jle", name !in labels);
    auto jna(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jna", name !in labels);
    auto jnae(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnae", name !in labels);
    auto jnb(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnb", name !in labels);
    auto jnbe(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnbe", name !in labels);
    auto jnc(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnc", name !in labels);
    auto jne(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jne", name !in labels);
    auto jng(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jng", name !in labels);
    auto jnge(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnge", name !in labels);
    auto jnl(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnl", name !in labels);
    auto jnle(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnle", name !in labels);
    auto jno(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jno", name !in labels);
    auto jnp(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnp", name !in labels);
    auto jns(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jns", name !in labels);
    auto jnz(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jnz", name !in labels);
    auto jo(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jo", name !in labels);
    auto jp(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jp", name !in labels);
    auto jpe(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jpe", name !in labels);
    auto jpo(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jpo", name !in labels);
    auto js(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "js", name !in labels);
    auto jz(string name) => branches ~= tuple(cast(ptrdiff_t)buffer.length, name, "jz", name !in labels);
        
    // auto rep(size_t size)
    // {
    //     buffer = buffer[0..(buffer.length - size)]~0xf3~buffer[(buffer.length - size)..$];
    //     return size + 1;
    // }
        
    // auto repe(size_t size)
    // {
    //     buffer = buffer[0..(buffer.length - size)]~0xf3~buffer[(buffer.length - size)..$];
    //     return size + 1;
    // }
        
    // auto repz(size_t size)
    // {
    //     buffer = buffer[0..(buffer.length - size)]~0xf3~buffer[(buffer.length - size)..$];
    //     return size + 1;
    // }
        
    // auto repne(size_t size)
    // {
    //     buffer = buffer[0..(buffer.length - size)]~0xf2~buffer[(buffer.length - size)..$];
    //     return size + 1;
    // }
        
    // auto repnz(size_t size)
    // {
    //     buffer = buffer[0..(buffer.length - size)]~0xf2~buffer[(buffer.length - size)..$];
    //     return size + 1;
    // }

    auto movs(Address!8 dst, Address!8 src) => emit!0(0xa4, dst, src);
    auto movs(Address!16 dst, Address!16 src) => emit!0(0xa5, dst, src);
    auto movs(Address!32 dst, Address!32 src) => emit!0(0xa5, dst, src);
    auto movs(Address!64 dst, Address!64 src) => emit!0(0xa5, dst, src);

    auto movsb() => emit!0(0xa4);
    auto movsw() => emit!0(0x66, 0xa5);
    auto movsd() => emit!0(0xa5);
    auto movsq() => emit!0(0x48, 0xa5);

    auto cmps(Address!8 dst, Address!8 src) => emit!0(0xa6, dst, src);
    auto cmps(Address!16 dst, Address!16 src) => emit!0(0xa7, dst, src);
    auto cmps(Address!32 dst, Address!32 src) => emit!0(0xa7, dst, src);
    auto cmps(Address!64 dst, Address!64 src) => emit!0(0xa7, dst, src);

    auto cmpsb() => emit!0(0xa6);
    auto cmpsw() => emit!0(0x66, 0xa7);
    auto cmpsd() => emit!0(0xa7);
    auto cmpsq() => emit!0(0x48, 0xa7);

    auto scas(Address!8 dst) => emit!0(0xae, dst);
    auto scas(Address!16 dst) => emit!0(0xaf, dst);
    auto scas(Address!32 dst) => emit!0(0xaf, dst);
    auto scas(Address!64 dst) => emit!0(0xaf, dst);

    auto scasb() => emit!0(0xae);
    auto scasw() => emit!0(0x66, 0xaf);
    auto scasd() => emit!0(0xaf);
    auto scasq() => emit!0(0x48, 0xaf);

    auto lods(Address!8 dst) => emit!0(0xac, dst);
    auto lods(Address!16 dst) => emit!0(0xad, dst);
    auto lods(Address!32 dst) => emit!0(0xad, dst);
    auto lods(Address!64 dst) => emit!0(0xad, dst);

    auto lodsb() => emit!0(0xac);
    auto lodsw() => emit!0(0x66, 0xad);
    auto lodsd() => emit!0(0xad);
    auto lodsq() => emit!0(0x48, 0xad);

    auto stos(Address!8 dst) => emit!0(0xaa, dst);
    auto stos(Address!16 dst) => emit!0(0xab, dst);
    auto stos(Address!32 dst) => emit!0(0xab, dst);
    auto stos(Address!64 dst) => emit!0(0xab, dst);

    auto stosb() => emit!0(0xaa);
    auto stosw() => emit!0(0x66, 0xab);
    auto stosd() => emit!0(0xab);
    auto stosq() => emit!0(0x48, 0xab);

    auto inal(ubyte imm8) => emit!0(0xe4, imm8);
    auto _in(ubyte imm8) => emit!0(0xe5, imm8);
    auto inal() => emit!0(0xec);
    auto _in() => emit!0(0xed);

    auto ins(Address!8 dst) => emit!0(0x6c, dst);
    auto ins(Address!16 dst) => emit!0(0x6d, dst);
    auto ins(Address!32 dst) => emit!0(0x6d, dst);

    auto insb() => emit!0(0x6c);
    auto insw() => emit!0(0x66, 0x6d);
    auto insd() => emit!0(0x6d);
    
    auto outal(ubyte imm8) => emit!0(0xe6, imm8);
    auto _out(ubyte imm8) => emit!0(0xe7, imm8);
    auto outal() => emit!0(0xee);
    auto _out() => emit!0(0xef);

    auto outs(Address!8 dst) => emit!0(0x6e, dst);
    auto outs(Address!16 dst) => emit!0(0x6f, dst);
    auto outs(Address!32 dst) => emit!0(0x6f, dst);

    auto outsb() => emit!0(0x6e);
    auto outsw() => emit!0(0x66, 0x6f);
    auto outsd() => emit!0(0x6f);

    auto seta(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x97, dst);
    auto setae(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x93, dst);
    auto setb(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x92, dst);
    auto setbe(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x96, dst);
    auto setc(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x92, dst);
    auto sete(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x94, dst);
    auto setg(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9f, dst);
    auto setge(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9d, dst);
    auto setl(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9c, dst);
    auto setle(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9e, dst);
    auto setna(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x96, dst);
    auto setnae(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x92, dst);
    auto setnb(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x93, dst);
    auto setnbe(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x97, dst);
    auto setnc(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x93, dst);
    auto setne(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x95, dst);
    auto setng(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9e, dst);
    auto setnge(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9c, dst);
    auto setnl(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9d, dst);
    auto setnle(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9f, dst);
    auto setno(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x91, dst);
    auto setnp(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9b, dst);
    auto setns(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x99, dst);
    auto setnz(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x95, dst);
    auto seto(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x90, dst);
    auto setp(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9a, dst);
    auto setpe(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9a, dst);
    auto setpo(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x9b, dst);
    auto sets(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x98, dst);
    auto setz(RM)(RM dst) if (valid!(RM, 8)) => emit!0(0x0f, 0x94, dst);

    Address!8 bytePtr(Args...)(Args args)
    {
        return Address!8(args);
    }

    Address!16 wordPtr(Args...)(Args args)
    {
        return Address!16(args);
    }

    Address!32 dwordPtr(Args...)(Args args)
    {
        return Address!32(args);
    }

    Address!64 qwordPtr(Args...)(Args args)
    {
        return Address!64(args);
    }

    Address!128 xmmwordPtr(Args...)(Args args)
    {
        return Address!128(args);
    }

    Address!256 ymmwordPtr(Args...)(Args args)
    {
        return Address!256(args);
    }

    Address!512 zmmwordPtr(Args...)(Args args)
    {
        return Address!512(args);
    }
}

import tern.digest;
import std.stdio;

unittest {
    Block!true block;
    with (block) {
        vaddps(xmm0, xmm1, xmm2);
        vaddps(xmm3, xmm4, xmm5);
        pxor(xmm3, xmm4);
        cvtss2sd(xmm2, xmm3);
    }

    assert(block.finalize().toHexString == 
        "C5F058C2" ~
        "C5D858DD" ~
        "660FEFDC" ~
        "F30F5AD3");
}

unittest {
    Block!true block;
    with (block) {
        movd(xmm0, ecx);
        movd(xmm0, r9d);
        movd(xmm8, ecx);
        movd(xmm8, r9d);
        movd(ecx, xmm0);
        movd(r9d, xmm0);
        movd(ecx, xmm8);
        movd(r9d, xmm8);
    }
    import std.stdio;
    //(block.finalize().toHexString);
    assert(block.finalize().toHexString == 
        "660F6EC1" ~
        "66410F6EC1" ~
        "66440F6EC1" ~
        "66450F6EC1" ~
        "660F7EC1" ~
        "66410F7EC1" ~
        "66440F7EC1" ~
        "66450F7EC1");
}

unittest {
    Block!true block;
    with (block) {
        push(rbp);
        mov(rbp, rsp);
        push(rbx);
        push(r12);
        push(r13);
        push(r14);
        push(r15);
        mov(esi, dwordPtr(rdi, 0x2b4));
        mov(rcx, qwordPtr(rdi, 128));
    }

    //(block.finalize().toHexString);
    // assert(block.finalize().toHexString == 
        // "488B8F80000000");
}

unittest {
    Block!true block;
    with (block) {
        movupd(xmm0, xmmwordPtr(rdi));
        movupd(xmm8, xmmwordPtr(rdi));
        movupd(xmmwordPtr(rdi), xmm0);
        movupd(xmmwordPtr(rdi), xmm8);
    }

    assert(block.finalize().toHexString == 
        "660F1007" ~
        "66440F1007" ~
        "660F1107" ~
        "66440F1107");
}

unittest {
    Block!true block;
    with (block) {
        vpbroadcastq(xmm0, xmm0);
        vpbroadcastq(xmm0, xmm8);
        vpbroadcastq(xmm8, xmm0);
        vpbroadcastq(xmm8, xmm8);
    }

    assert(block.finalize().toHexString == 
        "C4E27959C0" ~
        "C4C27959C0" ~
        "C4627959C0" ~
        "C4427959C0");
}

@("cvtsi2ss")
unittest {
    Block!true block;
    with (block) {
        cvtsi2ss(xmm0, ecx);
        cvtsi2ss(xmm0, r9d);
        cvtsi2ss(xmm8, ecx);
        cvtsi2ss(xmm8, r9d);
    }
    import std.stdio;
    //(block.finalize().toHexString);
    assert(block.finalize().toHexString == 
        "F30F2AC1" ~
        "F3410F2AC1" ~
        "F3440F2AC1" ~
        "F3450F2AC1");
}

// unittest
// {
//     Block!true block;
//     with (block)
//     {
//         mov(eax, ecx);
//         movsxd(rcx, eax);
//         mov(ebx, 1);
//         // TODO: pop and push are emitting REX but shouldn't
//         pop(rbx);
//         push(rcx);
//         jl("a");
//     label("a");
//         popf();
//         // Not supported in 64-bit
//         //pusha();
//         ret();
//         retf(3);
//         jmp("a");
//         jb("a");
//         setz(al);
//         //aad(17);
//         insb();
//         outal();
//         call(2);
//         lock(add(eax, ebx));
//         xacquire_lock(sub(si, di));
//         movsb();
//         // TODO: Make emittable instructions condiitonal?
//         //daa();
//         //das();
//         //aaa();
//         //pushcs();
//         mov(eax, code.dwordPtr(ebx));
//         // TODO: This is outputting 0x67 when it should output REX
//         mov(eax, code.dwordPtr(rbx));
//         //verr(si);
//         stc();
//         std();
//         clc();
//         wait();
//         fwait();
//         monitor();
//         lfence();
//         sfence();
//         retf();
//         test(al, bl);
//         hlt();
//         swapgs();
//         inc(eax);
//         dec(rax);
//         dec(rdi);
//         sub(rdi, 10);
//         mul(esi);
//         scasb();
//         cmpsb();
//         pause();
//         iret();
//         mov(esp, code.dwordPtr(rdx));
//         pop(rsp);
//         mov(rbp, rsp);
//     }
//     import tern.digest;
//     import std.stdio;
//     debug writeln(block.finalize().toHexString);
// }


@("shitter")
unittest
{
    Block!true block;
    with (block)
    {
        movzx(eax, ax);
        movzx(ecx, ax);
        movzx(eax, al);
        movzx(ecx, al);
        movsx(eax, ax);
        movsx(ecx, ax);
        movsx(eax, al);
        movsx(ecx, al);
    }
    import tern.digest;
    import std.stdio;
    writefln(block.finalize().toHexString);
    assert(block.finalize().toHexString == 
        "0FB7C00FB7C80FB6C00FB6C8" ~
        "0FBFC00FBFC80FBEC00FBEC8");
}

@("roundsd")
unittest
{
    Block!true block;
    with (block)
    {
        roundsd(xmm4, xmm5, 0);
        roundsd(xmm4, xmm5, 1);
        roundsd(xmm4, xmm5, 2);
        roundsd(xmm4, xmm5, 3);
    }
    import tern.digest;
    import std.stdio;
    writefln(block.finalize().toHexString);
    assert(block.finalize().toHexString == 
        "660F3A0BE500660F3A0BE501660F3A0BE502660F3A0BE503");
}

@("shufpd")
unittest
{
    Block!true block;
    with (block) {
        shufpd(xmm0, xmm2, 0x3);
    }

    import tern.digest;
    import std.stdio;
    writefln(block.finalize().toHexString);
    assert(block.finalize().toHexString == 
        "660FC6C203");
}