class De3 < Formula
  desc "Front end for the de3 hybrid multi-cloud / home-lab IaC ecosystem"
  homepage "https://github.com/philwyoungatinsight/de3-installer"
  # Private repo: the git download strategy authenticates through the user's git
  # credential helper, which `gh auth setup-git` configures. (A tarball download would
  # need a token.) Bump tag + revision on every release — the procedure is in
  # packaging/homebrew/README.md in the de3-installer repo.
  url "https://github.com/philwyoungatinsight/de3-installer.git",
      tag:      "v0.1.5",
      revision: "f363e7baa4b1331bf432e8cc6c7379da1008ff97"
  version "0.1.5"
  license :cannot_represent
  head "https://github.com/philwyoungatinsight/de3-installer.git", branch: "main"

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

    # The crux: the framework engine (`run`) is python3 and does `import yaml` /
    # `import packaging` at startup — before `de3 setup` ever runs. Vendor both into a
    # venv here, and have the wrapper below put that venv first on PATH, so the
    # `#!/usr/bin/env python3` entry points resolve to a python that can import them.
    venv = libexec/"venv"
    uv = Formula["uv"].opt_bin/"uv"
    ENV["UV_CACHE_DIR"] = buildpath/"uv-cache"   # keep uv's cache inside the build sandbox
    ENV["UV_PYTHON_DOWNLOADS"] = "never"         # use brew's python, never a downloaded one
    system uv, "venv", "--python", Formula["python@3.12"].opt_bin/"python3.12", venv
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
    assert_match "install-method=brew", shell_output("#{bin}/de3 env")
  end
end
