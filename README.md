# supreSSHion

A macOS menu bar agent that listens for screen lock and sleep events and then communicates with ssh-agent to unload keys
from memory. It can also temporarily disable this functionality as requested by the user. You can also view loaded keys
and unload all or selected keys via a dialog.

![supreSSHion screenshot](doc/supresshion_screenshot.png)

Requires macOS 15 Sequoia or later.

## How it works

When launched, supreSSHion registers itself as a listener for "screen is locked" and "workspace will sleep" events.

When it receives a lock event, it communicates with ssh-agent over its unix socket asking ssh-agent to unload all known
keys. It locates the unix socket via the `SSH_AUTH_SOCK` environment variable, which macOS sets automatically at login.

If the key removal functionality is disabled, lock events will not trigger key removal. When the screen is locked and
the expiration time of the disable has been reached, the keys will be removed.

When a sleep event is received, it will reactivate the key removal if the user had disabled the key unloading
functionality.

### What about loading my SSH key?

You can add `AddKeysToAgent yes` to your ssh config. If your key isn't loaded when ssh is invoked, ssh will prompt you
for your key. (You may also want to specify your key using `IdentityFile /path/to/id`.)

This approach works well for most terminal-based SSH usage, though it may not cover every tool that invokes SSH internally.

## License

supreSSHion is distributed under the [MIT License](LICENSE), and freely available for inclusion in other projects.

## Credits

App icon is [Forget by Gregor Cresnar from the Noun Project](https://thenounproject.com/term/forget/539392/). It is
licensed under [Creative Commons CCBY](https://creativecommons.org/licenses/by/3.0/us/).
