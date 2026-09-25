claude-podman
====

Claude for the security-conscious: run [claude-code, the claude cli tool](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview), in a rootless [podman](https://podman.io/) container.

Installation
----

First, download and install podman. Then install the script with curl. Set
`REPO` to match your fork (e.g. `?????/claude-podman`):

```sh
REPO=evancarroll/claude-podman
curl --proto '=https' --tlsv1.2 -sSf \
  "https://raw.githubusercontent.com/$REPO/refs/heads/main/bin/claude" |
  sed "s|^REPO_NAME=.*|REPO_NAME=$REPO|" |
  sudo tee /usr/local/bin/claude-podman > /dev/null
sudo chmod a+x /usr/local/bin/claude-podman
```

Now you can just run `claude-podman`.

Benefits
----

This provides the following benefits:

* Claude only gets file access to
	* Files in the present working directory
	* `$HOME/.claude.json`
	* `$HOME/.claude`
* Claude can only execute the files that exist in the image.

This image runs in rootless podman, and even inside rootless podman it runs as
a non-root user inside the container. Claude code is maximally locked down and
can't even update itself!

Customizing the runtime
----

Need to add packages to the container, or run an init script? no problem

```
--apk-packages foo,bar,baz # adds packages foo, bar, baz, with apk
--init-script  ./foobar.sh # copies foobar.sh into the container and executes it as root
```


For example, let's say you're using kubernetes and you do want claude to be able to troubleshoot it.

```sh
claude-podman \
	--apk-packages kubectl \
	--podman-arg "-v $HOME/.kube/config:/home/claude/.kube/config"
```

Surviving a wifi switch
----

Podman copies the host's resolvers into the container when it starts and never
refreshes them. Switch wifi mid-session and the container keeps querying DNS
servers that are no longer reachable, so lookups stall on timeouts until the
container is recreated. `--dns` pins resolution to servers of your choosing
instead, which is enough to keep a long session alive across the switch:

```sh
claude-podman --dns 1.1.1.1,1.0.0.1
```

The list is comma or space separated and replaces the host-derived servers
entirely.

A public resolver alone is not always enough: some networks drop or hijack
outbound port 53 to anything but their own server, and a captive portal blocks
everything until you log in. Listing a resolver from each network you use
covers that — whichever one is reachable answers:

```sh
claude-podman --dns 1.1.1.1,10.20.30.40
```

Things worth knowing before picking them:

* **The image is Alpine, so listed servers are queried in parallel.** musl's
  resolver sends the query to every `nameserver` at once and takes the first
  conclusive answer, rather than falling through one at a time the way glibc
  does. An unreachable server therefore costs nothing but a stray packet, and
  the order in the list carries no meaning.
* **Which means the servers must agree on their answers.** With parallel
  queries there is no "local first, public as fallback" — the reply that wins
  is whichever arrives first. Do not mix resolvers with different views of the
  same name, e.g. a split-horizon corporate server that resolves internal
  hostnames. Internal names are not reliably resolvable this way at all: a
  public resolver answering `NXDOMAIN` first is a conclusive answer.
* **Three is the ceiling.** musl reads at most three `nameserver` lines;
  anything beyond that is ignored.
* **Not everything in the container goes through musl.** The claude binary
  bundles c-ares, which does walk the list sequentially with its own timeout.
  If a dead server makes lookups sluggish, bound the wait with
  `--podman-arg "--dns-option=timeout:1" --podman-arg "--dns-option=attempts:1"`.

To apply the same servers to every container without passing the flag, set them
in `~/.config/containers/containers.conf` instead:

```toml
[containers]
dns_servers = ["1.1.1.1", "1.0.0.1"]
```

`--dns` composes with `--network`: on a dns-enabled podman network the
container's `resolv.conf` points only at aardvark-dns, and these servers become
its upstream, so resolving other containers by name keeps working.

Sharing a network with another container
----

By default the container uses podman's rootless network and can't reach other
containers by name. Use `--network NAME` to join a dedicated, user-defined
podman network (it's created automatically if it doesn't exist). Any other
container on the same network is then reachable from inside by its container
name, thanks to podman's built-in DNS.

```sh
# Start the service Claude should reach, on a shared network
podman run -d --name myservice --network claude-net some/image

# Run Claude on the same network (creates claude-net if needed)
claude-podman --network claude-net
```

Inside the container, Claude can now reach the service at `http://myservice:<port>`.
