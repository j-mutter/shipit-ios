require 'shipit-ios/version'
require 'highline/import'
require 'xcodeproj'
require 'nokogiri'
require 'plist'

module ShipitIos

  class Ship

    attr_reader :workspace, :project, :scheme, :configuration, :upload, :verbose

    def initialize(options={})
      @workspace      = options[:workspace]
      @project        = options[:project]
      @scheme         = options[:scheme]
      @configuration  = options[:configuration]
      @upload         = options[:upload]
      @verbose        = options[:verbose]
    end

    def it
      setup
      build
      shipit
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
        if files.length > 0
          puts "The following files look like they may be from a previous build:\n  #{files.join("\n  ")}"
          delete = agree("Delete them and build a new .ipa? (y/n)", true)
          if delete
            files.each do |f|
              File.delete(f)
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
        build_status = $?
        abort "Build failed -- aborting" unless build_status.success?
      end

      def shipit
        puts "Uploading previous build..." if @upload_old_build
        command = "xcrun -sdk iphoneos Validation -online -upload -verbose #{product_name}.ipa"
        puts "Upload command:\n #{command}" if verbose
        if upload
          `#{command}`
        else
          puts "To upload your app to iTunes Connect, be sure to set the --upload option"
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
