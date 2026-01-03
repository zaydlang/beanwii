module emu.hw.hollywood.vertexdecoder.decoder;

import config;
import emu.hw.hollywood.vertexdecoder.types;

static if (config_chosen_vertex_decoder_strategy == VertexDecoderStrategy.Interpreter) {
    public import emu.hw.hollywood.vertexdecoder.interpreter.decoder;
    alias VertexDecoder = VertexInterpreterDecoder;
} else static if (config_chosen_vertex_decoder_strategy == VertexDecoderStrategy.Jit) {
    public import emu.hw.hollywood.vertexdecoder.jit.decoder;
    alias VertexDecoder = VertexJitDecoder;
} else {
    static assert(false, "Unsupported vertex decoder strategy");
}
