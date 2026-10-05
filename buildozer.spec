[app]
title = Prueba Rich Text
package.name = richtexttest
package.domain = org.gestorherramientas

source.dir = .
source.include_exts = py,png,jpg,jpeg,kv,atlas,json,html,css,js
version = 0.1

requirements = python3,kivy,pyjnius

orientation = portrait
fullscreen = 0

android.permissions = INTERNET
android.api = 35
android.minapi = 24
android.accept_sdk_license = True
android.archs = arm64-v8a, armeabi-v7a

[buildozer]
log_level = 2
warn_on_root = 1
