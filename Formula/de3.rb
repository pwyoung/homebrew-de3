class De3 < Formula
  desc "Front end for the de3 hybrid multi-cloud / on-prem IaC ecosystem"
  homepage "https://github.com/philwyoungatinsight/de3-installer"
  # Private repo: the git download strategy authenticates through the user's git
  # credential helper, which `gh auth setup-git` configures. (A tarball download would
  # need a token.) Bump tag + revision on every release — the procedure is in
  # packaging/homebrew/README.md in the de3-installer repo.
  url "https://github.com/philwyoungatinsight/de3-installer.git",
      tag:      "v0.1.13",
      revision: "338a0d16b4b7b02b347feeb9719dca3fdd7f3c5b"
  version "0.1.13"
  license :cannot_represent
  head "https://github.com/philwyoungatinsight/de3-installer.git", branch: "main"

  # Platform gate. Homebrew itself settles the OS — it only runs on macOS and Linux, the
  # two de3 supports — but not *which* macOS. Big Sur (11) is the floor: the first arm64
  # release, and the oldest macOS Homebrew still supports, so below it the python@3.12 and
  # uv dependencies have no bottles to install from. Scoped to on_macos so the formula stays
  # usable under Linuxbrew, where a bare `depends_on macos:` would fail outright.
  on_macos do
    depends_on macos: :big_sur
  end

  # gh   — the de3 repos are private; every clone/pull authenticates through it.
  # uv   — the framework's Python tools build their per-tool venvs with uv, and we use it
  #        here too. Having brew supply it means `de3 setup` only adds the IaC toolchain.
  depends_on "gh"
  depends_on "git"
  depends_on "python@3.12"
  depends_on "uv"

  def install
    # Just the dispatcher — install.sh is the *other* install method and has no business
    # inside a keg (it would write untracked state into $HOME and fight brew over PATH).
    libexec.install "de3"
    # Sentinel read by `de3 update` (_install_method): under brew there's no checkout to
    # git-pull, so update must take the `brew upgrade` path.
    (libexec/"INSTALL_METHOD").write "brew\n"
    # Read by `de3 version` (_version): a keg has no .git, so `git describe` — how every
    # other install method answers — is unavailable here. Derived from the `version` above
    # rather than written out again, so it cannot drift from what brew actually built and
    # cutting a release stays the same three edits it already was. `v` prefix to match the
    # tag, so the string compares against `git describe` output.
    (libexec/"VERSION").write "v#{version}\n"

    # The crux: the framework engine (`run`) is python3 and does `import yaml` /
    # `import packaging` at startup — before `de3 setup` ever runs. Vendor both into a
    # venv here, and have the wrapper below put that venv first on PATH, so the
    # `#!/usr/bin/env python3` entry points resolve to a python that can import them.
    venv = libexec/"venv"
    uv = Formula["uv"].opt_bin/"uv"
    ENV["UV_CACHE_DIR"] = buildpath/"uv-cache"   # keep uv's cache inside the build sandbox
    ENV["UV_PYTHON_DOWNLOADS"] = "never"         # use brew's python, never a downloaded one
    system uv, "venv", "--python", Formula["python@3.12"].opt_bin/"python3.12", venv
    # Same versions install.sh pins for $DE3_HOME/venv — the two install methods must ship
    # the same Python environment. Bump both together, never one alone.
    system uv, "pip", "install", "--python", venv/"bin/python", "pyyaml==6.0.3", "packaging==26.3"

    # PATH: so the framework's python3 is the venv one. DE3_INSTALLED_VIA_BREW: the older
    # signal `de3 update` also accepts — set it so this formula works against a pinned
    # de3 that predates the INSTALL_METHOD sentinel.
    bin.write_env_script libexec/"de3", PATH: "#{venv}/bin:$PATH", DE3_INSTALLED_VIA_BREW: "1"
  end

  def caveats
    <<~EOS
      The de3 repos are private — authenticate once with the GitHub CLI:

        gh auth login

      Then:

        de3 setup             # install the IaC toolchain (jq, yq, sops, age, tofu, terragrunt, kubectl, helm)
        de3 list              # see what you can install
        de3 install <name>    # clone + bootstrap a stack, e.g. pwy-home-lab
        de3 doctor            # health check

      Everything de3 downloads lives under DE3_HOME (default ~/de3); `brew uninstall de3`
      does not remove it. Guide: docs/install-macos.md in the de3-installer repo.
    EOS
  end

  test do
    assert_match "de3 — front end for the de3 ecosystem", shell_output("#{bin}/de3 help")
    # The vendored venv must satisfy the framework engine's imports.
    system libexec/"venv/bin/python", "-c", "import yaml, packaging"
    # ...and it must be what a `#!/usr/bin/env python3` shebang resolves to under the wrapper.
    # The keg's VERSION file landed and `de3 version` reads it. Without this, a formula
    # bump that forgot the file would still pass while `de3 version` went quiet — in
    # exactly the install method that cannot fall back to `git describe`.
    assert_equal "de3 v#{version} (brew)", shell_output("#{bin}/de3 version").strip
    de3_env = shell_output("#{bin}/de3 env")
    assert_match "install-method=brew", de3_env
    # The dispatcher's own platform gate must agree with what brew just built for.
    assert_match(/platform=(Darwin|Linux)\//, de3_env)
  end
end
