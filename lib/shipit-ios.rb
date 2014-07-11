require 'shipit-ios/version'
require 'highline/import'
require 'xcodeproj'
require 'nokogiri'
require 'plist'
require 'fileutils'

module ShipitIos

  class Ship

    attr_reader :workspace, :project, :scheme, :configuration, :upload, :verbose

    def initialize(options={})
      @workspace      = options[:workspace]
      @project        = options[:project]
      @scheme         = options[:scheme]
      @configuration  = options[:configuration]
      @upload         = options[:upload]
      @archive        = options[:archive]
      @verbose        = options[:verbose]
    end

    def it
      setup
      build
      shipit
      archive
    end

    private

      def setup
        if upload
          puts <<-EOM
************************
**  Upload selected...
**  Make sure your app is in the 'Waiting for upload' state on iTunes connect
************************
          EOM
        end
        puts "Validating options and finding required files..." if verbose
        validate_options
        load_xcscheme
        load_plist
        puts "So far so good..." if verbose
        update_plist
        bump_build_number
      end

      def validate_options
        unless workspace || project
          abort "Please provide either a workspace or a project"
        end

        if workspace && project
          abort "Please provide a workspace OR project, not both"
        end

        workspace << '.xcworkspace' if workspace && !workspace.end_with?('.xcworkspace')
        project << '.xcodeproj' if project && !project.end_with?('.xcodeproj')

        abort "Unable to find file: #{root_file_path}" unless File.exists?(root_file_path)

        unless root_file_path && scheme
          abort "Missing option: A workspace or project are required, as well as a scheme"
        end

        @configuration = "Release" unless configuration
        unless build_configuration_names.include?(configuration)
          abort "Configuration #{configuration} does not exist in the scheme's target. Possible options are:\n  #{build_configuration_names.join("\n  ")} "
        end

      end

      def load_xcscheme
        abort "Specified scheme does not exist or is not shared" unless File.exists?(scheme_path)
        xcscheme
      end

      def load_plist
        abort "Cannot find plist file" unless File.exists?(plist_path)
        plist
      end

      def update_plist
        defaults = {:CFBundleIdentifier => plist['CFBundleIdentifier'],
                    :CFBundleShortVersionString => plist['CFBundleShortVersionString']}

        bundle_identifier = ask("Bundle Identifier: ") { |q| q.default = defaults[:CFBundleIdentifier]}
        version_string = ask("Version String: ") { |q| q.default = defaults[:CFBundleShortVersionString]}
        plist_changed = !(bundle_identifier == defaults[:CFBundleIdentifier] && version_string == defaults[:CFBundleShortVersionString])

        if plist_changed
          plist['CFBundleIdentifier'] = bundle_identifier
          plist['CFBundleShortVersionString'] = version_string
          puts "Updating #{File.basename(plist_path)}" if verbose
          File.open(plist_path, 'w') do |f|
            f.write plist.to_plist
          end
        end
      end

      def bump_build_number
        if agree("Bump build number? (y/n)", true)
          location = File.dirname(project_file_path_from_workspace)
          puts `cd #{location} && /usr/bin/agvtool bump -all`
        end
      end

      def build
        cleanup_old_build
        build_ipa unless @keep_old_build
      end

      def cleanup_old_build
        files = []
        [ipa_name, dsym_name].each do |f|
          files << f if File.exists?(f)
        end
        files += Dir.glob("*.xcarchive")
        if files.length > 0
          puts "The following files look like they may be from a previous build:\n  #{files.join("\n  ")}"
          delete = agree("Delete them and build a new .ipa? (y/n)", true)
          if delete
            files.each do |f|
              FileUtils.rm_r(f)
            end
          elsif files.include?(ipa_name)
            @keep_old_build = true
            @upload_old_build = agree("Do you want to upload the existing .ipa to iTunes Connect? (y/n)", false)
          end
        end
      end

      def build_ipa
        command_chunks = ['ipa build']
        if workspace
          command_chunks << "--workspace #{workspace}"
        else
          command_chunks << "--project #{project}"
        end
        command_chunks << "--scheme #{scheme}"
        command_chunks << "--configuration #{configuration}" if configuration
        command = command_chunks.join(' ')
        puts "Building .ipa"
        puts "Build command:\n#{command}" if verbose
        puts `#{command}`
        build_finished_time
        build_status = $?
        abort "Build failed -- aborting" unless build_status.success?
      end

      def shipit
        command = "xcrun -sdk iphoneos Validation -online -upload -verbose #{product_name}.ipa"
        puts "Upload command:\n#{command}" if verbose
        if upload
          check_keychain
          puts "Uploading previous build..." if @upload_old_build
          `#{command}`
        else
          puts "To upload your app to iTunes Connect, be sure to set the --upload option"
        end
      end

      def check_keychain
        search_results = find_keychain_password
        if $?.success?
          account = search_results.split.find {|line| line =~ /acct/}.split('"').last
          puts "Found a keychain item for iTunes Connect account: #{account}"
          if !agree("Use this account for upload? (y/n)", true)
            delete_keychain_password(account)
          else
            return
          end
        end
        puts "I need to add your iTunes Connect credentials to upload your build..."
        create_keychain_password
      end

      def find_keychain_password(account=nil)
        options = account ? {:a => account} : {}
        run_keychain_command(:find, options)
      end

      def create_keychain_password
        account = ask("iTunes Connect username/email: ")
        password = ask("Password for #{account}: ") { |q| q.echo = false }
        run_keychain_command(:add, {:a => account, :w => password, :U => nil})
      end

      def delete_keychain_password(account=nil)
        options = account ? {:a => account} : {}
        run_keychain_command(:delete, options)
      end

      def run_keychain_command(cmd='find', options={})
        command = "security #{cmd}-generic-password -s Xcode:itunesconnect.apple.com "
        command << options.map {|k,v| "-#{k} #{v}".strip}.join(' ')
        puts "Running keychain command:\n#{command}" if verbose
        `#{command}`
      end

      def archive
        return unless @archive && !@keep_old_build
        archive_path = File.expand_path("~/Library/Developer/Xcode/Archives/#{build_date}/#{archive_name}")
        if File.exists?(archive_path)
          puts "Copying xcarchive from #{archive_path}" if verbose
          `cp -r '#{archive_path}' '#{archive_name}'`
        else
          puts "Unable to locate #{archive_name} in #{File.dirname(archive_path)}"
        end
      end

      def root_file_path
        @root_file_path ||= File.expand_path(workspace || project)
      end

      def scheme_path
        @scheme_path ||= Xcodeproj::XCScheme.shared_data_dir(xcodeproject.path) + "#{scheme}.xcscheme"
      end

      def plist_path
        @plist_path ||= begin
          relative_path = build_settings["INFOPLIST_FILE"]
          project_dir = File.dirname(xcodeproject.path)
          project_dir + "/" + relative_path
        end
      end

      def target_name
        @target_name ||= xcscheme.xpath("//BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference").first["BlueprintName"]
      end

      def target
        @target ||= xcodeproject.targets.find { |t| t.name == target_name }
      end

      def build_configurations
        target.build_configurations
      end

      def build_configuration_names
        build_configurations.map { |c| c.name  }
      end

      def build_settings
        build_configurations.find { |c| c.name == configuration }.build_settings
      end

      def product_name
        @product_name ||= begin
          name = build_settings["PRODUCT_NAME"]
          return target_name if name == "$(TARGET_NAME)"
          name
        end
      end

      def ipa_name
        "#{product_name}.ipa"
      end

      def dsym_name
        "#{product_name}.app.dSYM.zip"
      end

      def build_status
        @build_status
      end

      def build_finished_time
        @build_finished_time ||= DateTime.now
      end

      def build_date
        build_finished_time.strftime("%Y-%m-%d").strip
      end

      def build_time
        build_finished_time.strftime("%l.%M %p").strip
      end

      def archive_name
        "#{product_name} #{build_date}, #{build_time}.xcarchive"
      end

      def plist
        @plist ||= Plist::parse_xml(plist_path)
      end

      def xcodeproject
        @xcodeproject ||= begin
          path = workspace ? project_file_path_from_workspace : root_file_path
          puts "Looking for project file at: #{path}" if verbose
          xcodeproject = Xcodeproj::Project.new(path)
          xcodeproject.initialize_from_file
          xcodeproject
        end
      end

      def xcscheme
        @xcscheme ||= Nokogiri::XML(File.open(scheme_path))
      end

      def project_file_path_from_workspace
        @project_file_path_from_workspace ||= begin
          puts "Loading workspace at: #{root_file_path}" if verbose
          xcworkspace = Xcodeproj::Workspace.new_from_xcworkspace(root_file_path)
          workspace_dir = File.dirname(root_file_path)
          all_projects = xcworkspace.file_references.select { |f| f.path.end_with?('.xcodeproj') }
          path = all_projects.each do |p|
            project_path = workspace_dir + "/" + p.path
            project_schemes = Xcodeproj::Project.schemes(project_path)
            if project_schemes.include?(scheme)
              puts "Found project with matching scheme at: #{project_path}" if verbose
              return project_path
            end
          end
        end
      end

  end

end
