`updater-3.1.js.txt` is the unchanged 3.1 bridge updater from commit
`4afd01e0576cf21e363e78ac5e040f993aaee385`, normalized to LF.

SHA-256: `13092676e9075cd21f7014ef0d7be215dfb54768840c547ef832d211d372a985`.

The upgrade test loads this historical implementation with its original release
constants and verifies the new package through its real validation, staging and
activation paths. It prevents new root module filenames from silently breaking
automatic upgrades for users who still run 3.1. This fixture never contacts GitHub.
