package com.carriez.flutter_hbb

/**
 * CubeRemote: 내가 남의 PC에 접속해 있는 동안(뷰어 세션) 앱 프로세스를 살려두는 포그라운드 서비스.
 *
 * 문제: MainService(포그라운드)는 "내 화면을 남에게 보여주는" 호스트 세션에서만 뜬다.
 * 뷰어 세션에는 포그라운드 서비스가 없어서 홈으로 나가면 안드로이드가 프로세스를 정리하고,
 * 그때 RemotePage.dispose()가 sessionClose를 호출해 연결이 끊긴다.
 * (MainActivity.onStop 의 FloatingWindowService 도 MainService.isReady 일 때만 뜬다.)
 *
 * 해결: 원격/파일전송 페이지가 열려 있는 동안만 이 서비스를 포그라운드로 띄워
 * 프로세스가 죽지 않게 한다. 페이지를 닫으면 바로 내린다.
 */

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PendingIntent.FLAG_IMMUTABLE
import android.app.PendingIntent.FLAG_UPDATE_CURRENT
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class ViewerSessionService : Service() {

    companion object {
        private const val logTag = "viewerSession"
        private const val CHANNEL_ID = "CubeRemoteSession"
        // MainService 의 DEFAULT_NOTIFY_ID(1)·클라이언트별 알림(100+)과 겹치지 않는 값
        private const val NOTIFY_ID = 7001
        const val EXTRA_PEER = "peer"

        @Volatile
        var isRunning = false
            private set

        fun start(context: Context, peer: String) {
            val intent = Intent(context, ViewerSessionService::class.java).putExtra(EXTRA_PEER, peer)
            // 포그라운드로 승격시킬 것이므로 O 이상에서는 startForegroundService 로 시작해야 한다.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ViewerSessionService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val peer = intent?.getStringExtra(EXTRA_PEER).orEmpty()
        // startForegroundService 로 시작했으면 5초 안에 반드시 startForeground 를 불러야
        // ANR(ForegroundServiceDidNotStartInTimeException)이 난다. 실패해도 앱을 죽이지 않는다.
        try {
            startForeground(NOTIFY_ID, buildNotification(peer))
            isRunning = true
            Log.d(logTag, "viewer session service started (peer=$peer)")
        } catch (e: Exception) {
            Log.e(logTag, "startForeground failed: ${e.message}")
            stopSelf()
        }
        // 시스템이 죽였다면 우리가 다시 띄울 이유가 없다(세션은 이미 끝난 것) → 재시작 안 함
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        Log.d(logTag, "viewer session service stopped")
        super.onDestroy()
    }

    private fun buildNotification(peer: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // IMPORTANCE_LOW: 소리·헤드업 없이 상태바에만 (원격 조작 중 방해되지 않게)
            val channel = NotificationChannel(
                CHANNEL_ID, "원격 연결", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "원격 지원 연결이 유지되는 동안 표시됩니다"
                lightColor = Color.BLUE
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        // 알림을 누르면 원격 화면으로 돌아온다(새 태스크를 만들지 않고 기존 것을 앞으로).
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE
        } else {
            FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, pendingFlags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setOngoing(true)                       // 스와이프로 지울 수 없게 = 연결 중임이 분명
            .setSmallIcon(R.mipmap.ic_stat_logo)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentTitle("큐브원격 연결 중")
            .setContentText(if (peer.isEmpty()) "탭하면 원격 화면으로 돌아갑니다" else "$peer · 탭하면 돌아갑니다")
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(pendingIntent)
            .setColor(ContextCompat.getColor(this, R.color.primary))
            .build()
    }
}
