require 'http'
require 'base64'
require 'pry'

APPALOOSA_SERVER = 'http://appaloosa-int.herokuapp.com/api/v1'
# APPALOOSA_SERVER = 'http://lvh.me:3000/api/v1'

module Fastlane
  module Actions
    class AppaloosaAction < Action
      def self.run(params)
        api_key = params[:api_token]
        store_id = params[:store_id]

        if request_email? api_key, store_id
          auth = create_an_account params[:email]
          api_key = auth['api_key']
          store_id = auth['store_id']
          return if error_detected auth['errors']
        end

        binary = normalize_binary_name params[:binary]
        remove_extra_screenshots_file params[:screenshots]
        screenshots_url = get_screenshots_links api_key, store_id, params[:screenshots], params[:locale], params[:device]
        binary_url = get_binary_link binary, api_key, store_id
        upload_on_appaloosa api_key, store_id, binary_url, screenshots_url, params[:group_ids]

        reset_original_binary_names binary, params[:binary]
      end

      def self.reset_original_binary_names(current_name, original_name)
        `mv "#{current_name}" "#{original_name}"`
      end

      def self.remove_extra_screenshots_file(screenshots_env)
        `rm "#{screenshots_env}/screenshots.html"` unless screenshots_env.size == 0
      end

      def self.get_binary_link(binary, api_key, store_id)
        key_s3 = upload_on_s3 binary
        get_s3_url api_key, store_id, key_s3
      end

      def self.normalize_binary_name(binary)
        binary_rename = binary.delete(' ')
        `mv "#{binary}" #{binary_rename}`
        binary_rename
      end

      def self.create_an_account(email)
        response = HTTP.post("#{APPALOOSA_SERVER}/bitrise_binaries/create_an_account", form: { email: email })
        JSON.parse response
      end

      def self.request_email?(api_key, store_id)
        api_key.size == 0 && store_id.size == 0
      end

      def self.upload_screenshots(screenshots)
        return if screenshots.nil?
        list = []
        list << screenshots.map do |screen|
          upload_on_s3 screen
        end
      end

      def self.get_uploaded_links(uploaded_screenshots, api_key, store_id)
        return if uploaded_screenshots.nil?
        urls = []
        urls << uploaded_screenshots.flatten.map do |url|
          get_s3_url api_key, store_id, url
        end
      end

      def self.get_screenshots_links(api_key, store_id, screenshots_path, locale, device)
        screenshots = get_screenshots screenshots_path, locale, device
        uploaded = upload_screenshots screenshots
        links = get_uploaded_links uploaded, api_key, store_id
        links.is_a?(Array) ? links.flatten : nil
      end

      def self.get_screenshots(screenshots_path, locale, device)
        get_env_value('screenshots').nil? ? locale = '' : locale.concat('/')
        device.nil? ? device = '' : device.concat('-')
        screenshots_path.strip.size > 0 ? screenshots_list(screenshots_path, locale, device) : nil
      end

      def self.screenshots_list(path, locale, device)
        list = `ls #{path}/#{locale}`.split

        list.map do |screen|
          next if screen.match(device).nil?
          "#{path}/#{locale}#{screen}" unless Dir.exist?("#{path}/#{locale}#{screen}")
        end.compact
      end

      def self.upload_on_appaloosa(api_key, store_id, binary_path, screenshots, group_ids)
        screenshots = set_all_screenshots_links screenshots
        response = HTTP.post("#{APPALOOSA_SERVER}/#{store_id}/applications/upload",
                             json: { store_id: store_id,
                                     api_key: api_key,
                                     application: {
                                       binary_path: binary_path,
                                       screenshot1: screenshots[0],
                                       screenshot2: screenshots[1],
                                       screenshot3: screenshots[2],
                                       screenshot4: screenshots[3],
                                       screenshot5: screenshots[4],
                                       group_ids: group_ids
                                     }
                                   })
        json_res = JSON.parse response
        puts json_res
      end

      def self.set_all_screenshots_links(screenshots)
        if screenshots.nil?
          screens = %w(screenshot1 screenshot2 screenshot3 screenshot4 screenshot5)
          screenshots = screens.map do |_k, v|
            v = ''
          end
        else
          missings = 5 - screenshots.count
          (1..missings).map do |_i|
            screenshots << ''
          end
        end
        screenshots
      end

      def self.get_s3_url(api_key, store_id, path)
        binary_path = HTTP.get("#{APPALOOSA_SERVER}/#{store_id}/bitrise_binaries/url_for_download",
          json: { store_id: store_id, api_key: api_key, key: path })
        json_res = JSON.parse binary_path
        return if error_detected json_res['errors']
        binary_path = json_res['binary_url']
      end

      def self.upload_on_s3(file)
        file_name = file.split('/').last
        response = HTTP.get("#{APPALOOSA_SERVER}/bitrise_binaries/fastlane",
          json: { file: file_name })
        json_res = JSON.parse response
        url = json_res['s3_sign']
        path = json_res['path']
        uri = URI.parse(Base64.decode64(url))
        File.open(file, 'rb') do |f|
          Net::HTTP.start(uri.host) do |http|
            http.send_request('PUT', uri.request_uri, f.read, 'content-type' => '')
          end
        end
        path
      end

      def self.get_env_value(option)
        available_options.map do |opt|
          opt if opt.key == option.to_sym
        end.compact[0].default_value
      end

      def self.error_detected(errors)
        if errors
          puts "ERROR: #{errors}".red
          true
        else
          false
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Upload your app to Appaloosa Store'
      end

      def self.details
        'You can use this action to do cool things...'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :binary,
                                       env_name: 'FL_APPALOOSA_BINARY',
                                       description: 'Path to your IPA or APK file. Optional for ipa if you use the `ipa` or `xcodebuild` action. For Mac zip the .app',
                                       default_value: Actions.lane_context[SharedValues::IPA_OUTPUT_PATH],
                                       verify_block: proc do |value|
                                         fail "Couldn't find ipa || apk file at path '#{value}'".red unless File.exist?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :api_token,
                                       env_name: 'FL_APPALOOSA_API_TOKEN',
                                       description: "Your API Token, if you don\'t have an account hit [enter]",
                                       verify_block: proc do
                                       end),
          FastlaneCore::ConfigItem.new(key: :store_id,
                                       env_name: 'FL_APPALOOSA_STORE_ID',
                                       description: "Your Store id, if you don\'t have an account hit [enter]",
                                       verify_block: proc do |_value|
                                       end),
          FastlaneCore::ConfigItem.new(key: :email,
                                       env_name: 'FL_APPALOOSA_EMAIL',
                                       description: "It's your first time? Give your email address",
                                       optional: false),
          FastlaneCore::ConfigItem.new(key: :group_ids,
                                       env_name: 'FL_APPALOOSA_GROUPS',
                                       description: 'Your app is limited to special users? Give us the group ids',
                                       default_value: '',
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :screenshots,
                                       env_name: 'FL_APPALOOSA_SCREENSHOTS',
                                       description: 'Add some screenshots application to your store or hit [enter]',
                                       default_value: Actions.lane_context[SharedValues::SNAPSHOT_SCREENSHOTS_PATH]),
          FastlaneCore::ConfigItem.new(key: :locale,
                                       env_name: 'FL_APPALOOSA_LOCALE',
                                       description: 'Select the folder locale for yours screenshots',
                                       default_value: 'en-US',
                                       optional: true
                                      ),
          FastlaneCore::ConfigItem.new(key: :device,
                                       env_name: 'FL_APPALOOSA_DEVICE',
                                       description: 'Select the device format for yours screenshots',
                                       optional: true
                                      ),
          FastlaneCore::ConfigItem.new(key: :development,
                                       env_name: 'FL_APPALOOSA_DEVELOPMENT',
                                       description: 'Create a development certificate instead of a distribution one',
                                       is_string: false,
                                       default_value: false,
                                       optional: true)
        ]
      end

      def self.authors
        ['Appaloosa']
      end

      def self.is_supported?(platform)
        platform == :ios
        # platform == :android
      end
    end
  end
end
