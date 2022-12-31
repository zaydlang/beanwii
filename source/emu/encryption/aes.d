module emu.encryption.aes;

import deimos.openssl.err;
import deimos.openssl.evp;
import util.log;
import util.number;

public void decrypt_aes(u8[] buf, u8[16] key, u8[16] iv, u8* out_buf) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (ctx is null) {
        error_encryption("Could not create OpenSSL cipher context.");
    }

    if (EVP_DecryptInit_ex(ctx, EVP_aes_128_cbc(), null, null, null) != 1) {
        error_encryption("Could not initialize OpenSSL cipher context.");
    }

    if (EVP_CIPHER_CTX_set_padding(ctx, 0) != 1) {
        error_encryption("Could not set OpenSSL cipher padding.");
    }

    if (EVP_DecryptInit_ex(ctx, null, null, key.ptr, iv.ptr) != 1) {
        error_encryption("Could not set OpenSSL cipher key and initialization vector.");
    }

    int outlen = 0;
    if (EVP_DecryptUpdate(ctx, out_buf, &outlen, buf.ptr, cast(int) buf.length) != 1) {
        error_encryption("Could not decrypt buf.");
    }

    log_encryption("Decrypted %d / %d bytes.", outlen, buf.length);

    if (outlen != buf.length) {
        error_encryption("Error. Did not decrypt all bytes.");
    }

    EVP_CIPHER_CTX_free(ctx);
}