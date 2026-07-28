package com.example.hyrox_training_tracker

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val backupChannel = "hyrox/data_backup"
    private val createBackupRequest = 4601
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveBackup") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("backup_busy", "已有文件保存操作正在进行", null)
                    return@setMethodCallHandler
                }
                val sourcePath = call.argument<String>("sourcePath")
                val suggestedName = call.argument<String>("suggestedName")
                if (sourcePath.isNullOrBlank() || !File(sourcePath).isFile) {
                    result.error("backup_missing", "待保存的备份文件不存在", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                pendingSourcePath = sourcePath
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, suggestedName ?: "HYROX_Backup.hyroxbackup")
                }
                startActivityForResult(intent, createBackupRequest)
            }
    }

    @Deprecated("Deprecated in Android SDK, required by FlutterActivity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != createBackupRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult
        val sourcePath = pendingSourcePath
        pendingResult = null
        pendingSourcePath = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(false)
            return
        }
        try {
            val output = contentResolver.openOutputStream(data.data!!, "w")
                ?: throw IllegalStateException("无法打开目标文件")
            output.use { stream ->
                File(sourcePath!!).inputStream().use { input ->
                    input.copyTo(stream)
                }
            }
            result?.success(true)
        } catch (error: Exception) {
            result?.error("backup_write_failed", error.message, null)
        }
    }
}
