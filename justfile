default:
    @just --list

# check the lua for syntax errors
check:
    luac -p workshop/Contents/mods/banditslargemaps/42/media/lua/*/*.lua

# link the mod into the game's workshop folder, to test and upload it in game
link:
    ln -sfn "{{justfile_directory()}}/workshop" ~/Zomboid/Workshop/banditslargemaps
