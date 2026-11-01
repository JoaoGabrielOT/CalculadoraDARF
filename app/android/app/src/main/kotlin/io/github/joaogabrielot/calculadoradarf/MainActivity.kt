package io.github.joaogabrielot.calculadoradarf

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "calculadoradarf/plataforma")
            .setMethodCallHandler { chamada, resultado ->
                if (chamada.method == "instalarApk") {
                    try {
                        instalarApk(chamada.argument<String>("caminho")!!)
                        resultado.success(null)
                    } catch (e: Exception) {
                        resultado.error("instalar_apk", e.message, null)
                    }
                } else {
                    resultado.notImplemented()
                }
            }
    }

    /** Abre o instalador do Android para o APK baixado (android/main.py:80, instalar_apk). */
    private fun instalarApk(caminho: String) {
        val uri = FileProvider.getUriForFile(this, "$packageName.provider", File(caminho))
        val intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(uri, "application/vnd.android.package-archive")
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}
