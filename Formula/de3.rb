class De3 < Formula
  desc "de3 command-line tool for managing DE3 infrastructure"
  homepage "https://github.com/philwyoungatinsight/de3-installer"
  
  # Using git source with v0.1.0 tag for private repo access
  url "https://github.com/philwyoungatinsight/de3-installer.git",
      using: :git,
      tag: "v0.1.0"
  version "0.1.0"
  
  depends_on "gh"
  depends_on "git"
  depends_on "python@3.12"
  depends_on "uv"
  
  # IaC toolchain - these would otherwise be installed by 'de3 setup'
  # Making them recommended means they're installed by default but can be skipped with --ignore-dependencies
  depends_on "jq" => :recommended
  depends_on "yq" => :recommended
  depends_on "age" => :recommended
  depends_on "sops" => :recommended
  depends_on "kubernetes-cli" => :recommended  # kubectl
  depends_on "helm" => :recommended
  depends_on "opentofu" => :recommended  # tofu
  depends_on "terragrunt" => :recommended
  
  def install
    # Create libexec directory for de3 scripts
    libexec.install "de3", "install.sh"
    
    # Create venv with pyyaml and packaging using uv
    venv_path = libexec/"venv"
    system "uv", "venv", venv_path, "--python", Formula["python@3.12"].opt_bin/"python3.12"
    system "uv", "pip", "install", "--python", venv_path/"bin"/"python", "pyyaml", "packaging"
    
    # Create wrapper script that prepends venv to PATH
    (bin/"de3").write <<~EOS
      #!/bin/bash
      # Homebrew wrapper for de3
      # Prepend venv to PATH so python3 finds pyyaml/packaging
      export PATH="#{venv_path}/bin:$PATH"
      
      # Mark as brew-installed for update detection
      export DE3_INSTALLED_VIA_BREW=1
      
      # Execute the real de3 script
      exec "#{libexec}/de3" "$@"
    EOS
    
    # Make wrapper executable
    chmod 0755, bin/"de3"
  end
  
  def caveats
    <<~EOS
      Before using de3, you must authenticate with GitHub:
        gh auth login
      
      Then run:
        de3 list     # List available packages
      
      Most IaC tools have been installed via Homebrew dependencies.
      Run 'de3 setup' to install any remaining tools or verify the installation.
      
      To update de3:
        de3 update
      (This will use brew upgrade when installed via Homebrew)
    EOS
  end
  
  test do
    # Basic test to ensure de3 script exists and is executable
    assert_predicate bin/"de3", :exist?
    assert_predicate bin/"de3", :executable?
    
    # Test that de3 can show help without errors
    system bin/"de3", "help"
  end
end