package `in`.easycloud.sheetal_partner

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createDeliveryOfferChannels()
    }

    private fun createDeliveryOfferChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return

        val alarmAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

        // Loud channel for lock-screen / background delivery offers
        val alert = NotificationChannel(
            "delivery_offers_alert",
            "Delivery offers (alert)",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Loud alerts for new nearby delivery requests"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 600, 400, 600, 400, 800)
            setSound(alarmUri, alarmAttrs)
            setBypassDnd(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }

        val normal = NotificationChannel(
            "delivery_offers",
            "Delivery offers",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New nearby Sheetal delivery requests"
            enableVibration(true)
            setSound(alarmUri, alarmAttrs)
        }

        manager.createNotificationChannel(alert)
        manager.createNotificationChannel(normal)
    }
}
