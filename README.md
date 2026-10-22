# Speakeasy

Speakeasy is a small menu-bar app for macOS 27. When you're using the built-in Dictation and press Return, it stops Dictation and then sends the Return, the way most third-party dictation apps work. Everything you said makes it into the text first, including the words still being transcribed when you hit the key.

When Dictation is off, Speakeasy leaves Return alone.

## How it works

macOS doesn't offer a setting or an API for this, so Speakeasy relies on two things the system already does.

Dictation's background process (`DictationIM`) writes a line to the system log whenever it starts or stops listening. Speakeasy follows that log with `log stream`, so it always knows whether Dictation is on.

When you press Return while Dictation is on, Speakeasy holds the key and presses Edit > Stop Dictation in the app you're typing in. It finds that menu item through Accessibility by its internal identifier, so it works in any language. Stopping this way matches what the microphone key does, and Dictation finishes transcribing before it shuts off. Once the log says the session is over, Speakeasy sends your Return with any modifier keys you were holding.

A few apps have no Stop Dictation menu item. In those, Speakeasy sends Escape instead. Escape also stops Dictation, but it throws away audio that hasn't been transcribed yet, so the last word or two can go missing.

The log lines Speakeasy watches aren't documented by Apple. If a macOS update changes them, Speakeasy stops reacting and Return goes back to its normal behavior.

## Building

You need a Mac running macOS 27 with Xcode 27 installed. Xcode supplies `actool` for the icon as well as the Swift compiler.

```
./build.sh
```

That builds `build/Speakeasy.app`, compiles the app icon from `Speakeasy.icon` (an Icon Composer file you can open in Icon Composer to edit), signs the app, copies it to `~/Applications`, and launches it. Use `./build.sh --no-install` to build and sign without installing.

On first launch, macOS asks you to give Speakeasy Accessibility access, which it needs to see the Return key and press the menu item. It also adds itself to your login items. You can turn either feature off from the menu-bar icon.

If you have no Developer ID certificate, `build.sh` signs the app ad-hoc, and that works fine. The catch is that macOS ties the Accessibility permission to the signature, and an ad-hoc signature changes with every build. After each rebuild you'll need to remove Speakeasy from the Accessibility list in System Settings and add it again. If you have your own Developer ID, run `SPEAKEASY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh` and the permission will carry over between builds.

## Privacy

Speakeasy watches the keyboard because it has to catch Return, but it ignores every other key. It never records or stores what you type and makes no network connections. The only thing it reads from the system log is Dictation's own on and off messages. The source is short, and `Sources/main.swift` is the whole app if you want to check.

## The menu-bar icon

The icon shows a return arrow while Speakeasy is waiting and a microphone while Dictation is on. A warning triangle means it still needs Accessibility access. The menu lets you pause Speakeasy, choose whether it opens at login, or quit.

## Probe

`probe/probe.swift` is the diagnostic tool we used to look for a reliable "Dictation is on" signal. It logs on-screen windows and which processes are using the microphone. Neither turned out to be reliable, which is why Speakeasy reads the log instead. Build it with `swiftc -O probe/probe.swift -o probe/probe`.

## License

MIT. See `LICENSE`.
