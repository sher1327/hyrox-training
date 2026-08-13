package com.example.hyrox_training_tracker

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val backupChannel = "hyrox/data_backup"
    private val blePermissionChannel = "hyrox/ble_permissions"
    private val createBackupRequest = 4601
    private val blePermissionRequest = 4602
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null
    private var pendingBlePermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, backupChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveBackup") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingBackupResult != null) {
                    result.error("backup_busy", "已有文件保存操作正在进行", null)
                    return@setMethodCallHandler
                }
                val sourcePath = call.argument<String>("sourcePath")
                val suggestedName = call.argument<String>("suggestedName")
                if (sourcePath.isNullOrBlank() || !File(sourcePath).isFile) {
                    result.error("backup_missing", "待保存的备份文件不存在", null)
                    return@setMethodCallHandler
                }
                pendingBackupResult = result
                pendingSourcePath = sourcePath
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, suggestedName ?: "HYROX_Backup.hyroxbackup")
                }
                startActivityForResult(intent, createBackupRequest)
            }

        MethodChannel(messenger, blePermissionChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "requestPermissions") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                requestBlePermissions(result)
            }
    }

    private fun requestBlePermissions(result: MethodChannel.Result) {
        if (pendingBlePermissionResult != null) {
            result.error("permission_busy", "蓝牙权限请求正在进行", null)
            return
        }
        val required = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val missing = required.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        pendingBlePermissionResult = result
        requestPermissions(missing.toTypedArray(), blePermissionRequest)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != blePermissionRequest) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            return
        }
        val result = pendingBlePermissionResult
        pendingBlePermissionResult = null
        result?.success(
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED },
        )
    }

    @Deprecated("Deprecated in Android SDK, required by FlutterActivity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != createBackupRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingBackupResult
        val sourcePath = pendingSourcePath
        pendingBackupResult = null
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
