require File.expand_path('../../spec_helper', __FILE__)

describe "gemfile install with gem sources" do
  it "prints output and returns if no dependencies are specified" do
    gemfile <<-G
      source "file://#{gem_repo1}"
    G

    bundle :install
    out.should =~ /no dependencies/
  end

  it "fetches gems" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem 'rack'
    G

    default_bundle_path("gems/rack-1.0.0").should exist
    should_be_installed("rack 1.0.0")
  end

  it "pulls in dependencies" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
    G

    should_be_installed "actionpack 2.3.2", "rails 2.3.2"
  end

  it "does the right version" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack", "0.9.1"
    G

    should_be_installed "rack 0.9.1"
  end

  it "does not install the development dependency" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "with_development_dependency"
    G

    should_be_installed "with_development_dependency 1.0.0"
    should_not_be_installed "activesupport 2.3.5"
  end

  it "resolves correctly" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "activemerchant"
      gem "rails"
    G

    should_be_installed "activemerchant 1.0", "activesupport 2.3.2", "actionpack 2.3.2"
  end

  it "activates gem correctly according to the resolved gems" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "activesupport", "2.3.5"
    G

    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "activemerchant"
      gem "rails"
    G

    should_be_installed "activemerchant 1.0", "activesupport 2.3.2", "actionpack 2.3.2"
  end

  it "does not reinstall any gem that is already available locally" do
    system_gems "activesupport-2.3.2"

    build_repo2 do
      build_gem "activesupport", "2.3.2" do |s|
        s.write "lib/activesupport.rb", "ACTIVESUPPORT = 'fail'"
      end
    end

    install_gemfile <<-G
      source "file://#{gem_repo2}"
      gem "activerecord", "2.3.2"
    G

    should_be_installed "activesupport 2.3.2"
  end

  it "works when the gemfile specifies gems that only exist in the system" do
    build_gem "foo", :to_system => true
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      gem "foo"
    G

    should_be_installed "rack 1.0.0", "foo 1.0.0"
  end

  it "prioritizes local gems over remote gems" do
    build_gem 'rack', '1.0.0', :to_system => true do |s|
      s.add_dependency "activesupport", "2.3.5"
    end

    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    should_be_installed "rack 1.0.0", "activesupport 2.3.5"
  end

  it "installs gems for the correct platform" do
    Gem.platforms = [rb]
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "platform_specific"
    G

    run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
    out.should == "1.0.0 #{Gem::Platform.local}"
  end

  describe "with extra sources" do

    it "finds gems in multiple sources" do
      build_repo2
      update_repo2

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        source "file://#{gem_repo2}"

        gem "activesupport", "1.2.3"
        gem "rack", "1.2"
      G

      should_be_installed "rack 1.2", "activesupport 1.2.3"
    end

  end

  describe "when locked" do
    before(:each) do
      system_gems "rack-0.9.1" do
        gemfile <<-G
          source "file://#{gem_repo1}"
          gem "rack"
        G

        bundle :lock
      end
    end

    it "works" do
      system_gems [] do
        bundle :install
        should_be_installed "rack 0.9.1"
      end
    end

    it "allows --relock to update the dependencies" do
      system_gems "rack-0.9.1" do
        bundle "install --relock"
        should_be_installed "rack 1.0.0"
      end
    end

    it "regenerates .bundle/environment.rb if missing" do
      bundled_app('.bundle/environment.rb').delete
      system_gems [] do
        bundle :install
        bundled_app('.bundle/environment.rb').should exist
        should_be_installed "rack 0.9.1"
      end
    end
  end

  describe "with BUNDLE_PATH set" do
    before :each do
      build_lib "rack", "1.0.0", :to_system => true do |s|
        s.write "lib/rack.rb", "raise 'FAIL'"
      end

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
    end

    it "installs gems to BUNDLE_PATH" do
      ENV['BUNDLE_PATH'] = bundled_app('vendor').to_s

      bundle :install

      bundled_app('vendor/gems/rack-1.0.0').should be_directory
      should_be_installed "rack 1.0.0"
    end

    it "installs gems to BUNDLE_PATH from .bundle/config" do
      config "BUNDLE_PATH" => bundled_app("vendor").to_s

      bundle :install

      bundled_app('vendor/gems/rack-1.0.0').should be_directory
      should_be_installed "rack 1.0.0"
    end

    it "installs gems to BUNDLE_PATH relative to root when relative" do
      ENV['BUNDLE_PATH'] = 'vendor'

      FileUtils.mkdir_p bundled_app('lol')
      Dir.chdir(bundled_app('lol')) do
        bundle :install
      end

      bundled_app('vendor/gems/rack-1.0.0').should be_directory
      should_be_installed "rack 1.0.0"
    end

    it "sets BUNDLE_PATH as the first argument to bundle install" do
      bundle "install ./vendor"

      bundled_app('vendor/gems/rack-1.0.0').should be_directory
      should_be_installed "rack 1.0.0"
    end

    it "does not disable system gems when specifying a path to install to" do
      build_gem "rack", "1.1.0", :to_system => true
      bundle "install ./vendor"

      bundled_app('vendor/gems/rack-1.1.0').should_not be_directory
      should_be_installed "rack 1.1.0"
    end
  end

  describe "disabling system gems" do
    before :each do
      build_gem "rack", "1.0.0", :to_system => true do |s|
        s.write "lib/rack.rb", "puts 'FAIL'"
      end
    end

    it "does not use available system gems" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "install --disable-shared-gems"
      should_be_installed "rack 1.0.0"
    end

    it "remembers to disable system gems after the first time" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "install vendor/gems --disable-shared-gems"
      FileUtils.rm_rf bundled_app('vendor/gems')
      bundle "install"

      bundled_app('vendor/gems/gems/rack-1.0.0').should be_directory
      should_be_installed "rack 1.0.0"
    end
  end

  describe "when cached and locked" do
    it "does not hit the remote at all" do
      build_repo2
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "rack"
      G

      bundle :lock
      bundle :cache

      system_gems []
      FileUtils.rm_rf gem_repo2

      bundle :install
      should_be_installed "rack 1.0.0"
    end
  end

  describe "when specifying groups not excluded" do
    before :each do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        group :emo do
          gem "activesupport", "2.3.5"
        end
      G
    end

    it "installs gems in the default group" do
      should_be_installed "rack 1.0.0"
    end

    it "installs gems in other groups" do
      should_be_installed "activesupport 2.3.5"
    end

    it "sets up everything if Bundler.setup is used with no groups" do
      out = run("require 'rack'; puts RACK")
      out.should == '1.0.0'

      out = run("require 'activesupport'; puts ACTIVESUPPORT")
      out.should == '2.3.5'
    end
  end

  describe "when excluding groups" do
    before :each do
      install_gemfile <<-G, 'without' => 'emo'
        source "file://#{gem_repo1}"
        gem "rack"
        group :emo do
          gem "activesupport", "2.3.5"
        end
      G
    end

    it "installs gems in the default group" do
      should_be_installed "rack 1.0.0", :groups => [:default]
    end

    it "does not install gems from the excluded group" do
      should_not_be_installed "activesupport 2.3.5", :groups => [:default]
    end

    it "does not say it installed gems from the excluded group" do
      out.should_not include("activesupport")
    end

    it "allows Bundler.setup for specific groups" do
      out = run("require 'rack'; puts RACK", :default)
      out.should == '1.0.0'
    end
  end
end