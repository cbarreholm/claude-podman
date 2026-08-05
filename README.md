opencode-podman
====

[opencode](https://opencode.ai/) for the security-conscious: run the opencode
terminal agent in a rootless [podman](https://podman.io/) container.

This is a fork of [claude-podman](https://github.com/EvanCarroll/claude-podman)
adapted for opencode.

Installation
----

First, download and install podman. Then install the script with curl. Set
`REPO` to match your fork (e.g. `?????/opencode-podman`):

```sh
REPO=ingby/opencode-podman
curl --proto '=https' --tlsv1.2 -sSf \
  "https://raw.githubusercontent.com/$REPO/refs/heads/main/bin/opencode" |
  sed "s|^REPO_NAME=.*|REPO_NAME=$REPO|" |
  sudo tee /usr/local/bin/opencode-podman > /dev/null
sudo chmod a+x /usr/local/bin/opencode-podman
```

Now you can just run `opencode-podman`.

Benefits
----

This provides the following benefits:

* opencode only gets file access to
	* Files in the present working directory
	* `$HOME/.config/opencode` (config)
	* `$HOME/.local/share/opencode` (auth, sessions)
	* `$HOME/.local/state/opencode` (state)
* opencode can only execute the files that exist in the image.

This image runs in rootless podman, and even inside rootless podman it runs as
a non-root user inside the container.

Supply chain hardening
----

The image does **not** use opencode's `curl | bash` installer, and opencode
cannot update itself:

* The build downloads a single, explicitly pinned release tarball
  (`opencode-linux-*-musl.tar.gz`) from GitHub. The version **and** its
  sha256 checksum are committed in `devops/build-image.sh`; the build fails
  if the downloaded artifact does not match.
* Autoupdate is disabled three ways:
	* `OPENCODE_DISABLE_AUTOUPDATE=true` is baked into the image (authoritative
	  — it wins even if a mounted config says otherwise).
	* The image ships `~/.config/opencode/opencode.json` with
	  `"autoupdate": false`, and the wrapper writes the same config on the
	  host if none exists yet.
	* The binary lives at `/usr/local/bin/opencode`, owned by root, so the
	  container user could not overwrite it anyway.

To upgrade opencode: edit `OPENCODE_VERSION` and the two `OPENCODE_SHA256_*`
values in `devops/build-image.sh` (download the new tarballs and run
`sha256sum` on them), then rebuild.

Customizing the runtime
----

Need to add packages to the container, or run an init script? no problem

```
--apk-packages foo,bar,baz # adds packages foo, bar, baz, with apk
--init-script  ./foobar.sh # copies foobar.sh into the container and executes it as root
```


For example, let's say you're using kubernetes and you do want opencode to be
able to troubleshoot it.

```sh
opencode-podman \
	--apk-packages kubectl \
	--podman-arg "-v $HOME/.kube/config:/home/opencode/.kube/config"
```

Sharing a network with another container
----

By default the container uses podman's rootless network and can't reach other
containers by name. Use `--network NAME` to join a dedicated, user-defined
podman network (it's created automatically if it doesn't exist). Any other
container on the same network is then reachable from inside by its container
name, thanks to podman's built-in DNS.

```sh
# Start the service opencode should reach, on a shared network
podman run -d --name myservice --network opencode-net some/image

# Run opencode on the same network (creates opencode-net if needed)
opencode-podman --network opencode-net
```

Inside the container, opencode can now reach the service at
`http://myservice:<port>`.
