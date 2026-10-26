# Can't Read
Auto-translation addon for chat. Pick your target language (the one that it will be translated to) by launching the batch file.

More languges to come.

Currently supported languages:
- English (english.bat)
- Français (français.bat)
- Português (português.bat)
- Deutsch (deutsch.bat)
- 한국어 (한국어.bat)
- русский (русский.bat)
- 中国人 (中国人.bat)
- espanol (espanol.bat)
- svenska (svenska.bat)
- nederlands (nederlands.bat)
- turkce (turkce.bat)
## You must go to your Documents/AAClassic/Addon/cant_read folder and launch your target language's batch file. This window must stay open while you are playing for translations to come through.

## How translation works
The batch window sends each chat message to free translation services, no account or key needed. It tries them in this order and moves on to the next one when one is busy or blocked:
1. Google
2. Google (the endpoint used by the Chrome extension)
3. MyMemory (about 5,000 characters a day; put your email in `$MYMEMORY_EMAIL` at the top of `scripts/google_translate.ps1` to raise it to 50,000)

Messages already in your language aren't shown. Item links are translated as the item's name. Busy chat is queued, so messages arriving close together are all translated.

## Privacy
Chat text (including whispers) is sent to those services to be translated. Player names are not sent.
