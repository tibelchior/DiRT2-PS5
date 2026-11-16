# Your game files go here

Copy your own **Colin McRae: DiRT 2** folder (PC, version 1.1, Steam) into this folder, so that
this file exists:

```
gamedata/Dirt 2/dirt2_game.exe
```

(`gamedata/dirt2_game.exe` works too.) Nothing in this folder is ever committed or uploaded;
`build.sh` reads `dirt2_game.exe` to recompile it and copies the folder into the finished title.
