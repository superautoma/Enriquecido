package org.gestorherramientas.gestor_herramientas_quill_test

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyStore
import java.security.Signature
import java.security.spec.RSAPublicKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device-local credentials are encrypted and excluded from Android/app ZIP backups. */
class ToolAi(private val activity: Activity, engine: FlutterEngine) {
    private val alias = "gestor_chatgpt_credentials_v1"
    private val file = AtomicFile(File(activity.noBackupFilesDir, "chatgpt_credentials.bin"))
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "org.gestorherramientas/tool_ai")

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> result.success(read())
                    "write" -> {
                        val text = call.argument<String>("value") ?: error("Missing value")
                        require(text.toByteArray().size <= 1024 * 1024)
                        write(text)
                        result.success(null)
                    }
                    "openBrowser" -> {
                        val uri = Uri.parse(call.argument<String>("url") ?: error("Missing URL"))
                        require(uri.scheme == "https" && uri.userInfo == null &&
                            uri.host in setOf("auth.openai.com", "chatgpt.com"))
                        activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(null)
                    }
                    "verifySignature" -> result.success(verifySignature(
                        call.argument<String>("token") ?: "",
                        call.argument<String>("jwks") ?: ""))
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                // Never return a credential, authorization URL or token-bearing exception.
                result.error("chatgpt_device_error", "No se pudo completar la operación en este dispositivo.", null)
            }
        }
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    private fun read(): String? {
        if (!file.baseFile.exists()) return null
        val bytes = file.openRead().use { it.readBytes() }
        require(bytes.size > 28 && bytes.size <= 1024 * 1024 + 64)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
    }

    private fun write(text: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val bytes = cipher.iv + cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        val stream = file.startWrite()
        try {
            stream.write(bytes)
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    private fun decode(value: String) = Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

    private fun verifySignature(token: String, jwks: String): Boolean {
        if (token.length > 65536 || jwks.length > 1024 * 1024) return false
        val parts = token.split('.')
        if (parts.size != 3) return false
        val header = JSONObject(decode(parts[0]).toString(Charsets.UTF_8))
        if (header.optString("alg") != "RS256" || header.has("crit")) return false
        val kid = header.optString("kid")
        if (kid.isEmpty()) return false
        val keys = JSONObject(jwks).getJSONArray("keys")
        for (i in 0 until keys.length()) {
            val jwk = keys.getJSONObject(i)
            if (jwk.optString("kid") != kid || jwk.optString("kty") != "RSA") continue
            if (jwk.has("use") && jwk.optString("use") != "sig") continue
            if (jwk.has("alg") && jwk.optString("alg") != "RS256") continue
            val modulus = BigInteger(1, decode(jwk.getString("n")))
            if (modulus.bitLength() < 2048) return false
            val publicKey = KeyFactory.getInstance("RSA").generatePublic(
                RSAPublicKeySpec(modulus, BigInteger(1, decode(jwk.getString("e")))))
            val verifier = Signature.getInstance("SHA256withRSA")
            verifier.initVerify(publicKey)
            verifier.update("${parts[0]}.${parts[1]}".toByteArray(Charsets.US_ASCII))
            return verifier.verify(decode(parts[2]))
        }
        return false
    }

    fun dispose() { channel.setMethodCallHandler(null) }
}
