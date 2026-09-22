package com.example.mobile

import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // installSplashScreen() dipanggil manual (bukan mengandalkan mekanisme
    // implisit Flutter) untuk mengatasi BLOKIR-D: splash macet permanen kalau
    // Activity ini dibuat lewat trampoline share-sheet Android (ACTION_SEND),
    // bukan tap launcher biasa. Ini memberi kontrol dismiss yang terikat ke
    // sinyal draw-pertama Activity di level Android, konsisten di semua jalur
    // peluncuran -- bukan ke deteksi first-frame Flutter yang ternyata tidak
    // selalu terpicu benar lewat jalur trampoline itu.
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }
}
