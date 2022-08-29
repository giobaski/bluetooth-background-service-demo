package com.example.bg_demo

import com.pauldemarco.flutter_blue.FlutterBluePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry
import io.flutter.plugin.platform.PlatformViewsController
import id.flutter.flutter_background_service.FlutterBackgroundServicePlugin


class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {

//        super.configureFlutterEngine(flutterEngine) //missing this
        GeneratedPluginRegistrant.registerWith(flutterEngine)
//        GeneratedPluginRegister.registerGeneratedPlugins(FlutterEngine(this))
//        FlutterBluePlugin.registerWith(flutterEngine)
//        GeneratedPluginRegistrant.registerWith(ShimPluginRegistry(flutterEngine))




//        val shimPluginRegistry = ShimPluginRegistry(flutterEngine)
//        FlutterBluePlugin.registerWith(shimPluginRegistry.registrarFor(com.pauldemarco.flutter_blue.FlutterBluePlugin))

//        FlutterBackgroundServicePlugin.registerWith(shimPluginRegistry.registrarFor(id.flutter.flutter_background_service.FlutterBackgroundServicePlugin))
    }

//
//    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//        // Create a ShimPluginRegistry and wrap the FlutterEngine with the shim.
//        val shimPluginRegistry = ShimPluginRegistry(flutterEngine, PlatformViewsController())
//        shimPluginRegistry.registrarFor(com.pauldemarco.flutter_blue.FlutterBluePlugin)
//
//        // Use the GeneratedPluginRegistrant to add every plugin that's in the pubspec.
//        GeneratedPluginRegistrant.registerWith(shimPluginRegistry);
//        registerFlutterCallbacks(flutterEngine)
//    }
}
