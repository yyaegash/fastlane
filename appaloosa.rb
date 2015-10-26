require "http"
require "base64"
require 'pry'

APPALOOSA_SERVER = "http://lvh.me:3000/api/v1"

module Fastlane
  module Actions
    module SharedValues
    end

    class AppaloosaAction < Action
      def self.run(params)
        api_key = params[:api_token]
        store_id = params[:store_id]
        
        request_email = api_key.size == 0 && store_id.size == 0
        if request_email
          response = HTTP.post("#{APPALOOSA_SERVER}/bitrise_binaries/create_an_account", :form => {:email => "#{params[:email]}"})
          json_res = JSON.parse response
          api_key = json_res['api_key']
          store_id = json_res['store_id']
          return if error_detected json_res['errors']
        elsif params[:api_token].size == 0 && params[:store_id].size == 0
          return error_detected 'Missing authentification values'
        end

        bin = params[:binary]
        bin = bin.gsub(' ', '')
        `mv "#{params[:binary]}" #{bin}`
        `rm "#{params[:screenshots]}/screenshots.html"` unless params[:screenshots].nil?

        params[:screenshots]
        screenshots_url = upload_and_render_screenshot_links api_key, store_id, params[:screenshots], params[:language], params[:device]
        
        key_s3 = upload_on_s3 bin
        binary_path = get_s3_url api_key, store_id, key_s3

        upload_on_appaloosa api_key, store_id, binary_path, screenshots_url, params[:group_ids]
        
        `mv "#{bin}" "#{params[:binary]}"`
      end

      def self.upload_and_render_screenshot_links api_key, store_id, screenshots_path, locale, device
        screenshots = get_screenshots screenshots_path, locale, device
        unless screenshots.nil?
          list = []
          list << screenshots.map do |screen|
            upload_on_s3 screen
          end
          urls = []
          urls << list.flatten.map do |url|
            get_s3_url api_key, store_id, url
          end
        end
        urls = urls.is_a?(Array) ? urls.flatten : nil        
      end

      def self.get_screenshots screenshots_path, locale, device
        get_env_value('screenshots').nil? ? locale = '' : locale.concat('/')
        device.nil? ? device = '' : device.concat('-')
        screenshots_path.strip.size > 0 ? screenshots_list(screenshots_path, locale, device) : nil
      end

      def self.screenshots_list path, locale, device
        list = `ls #{path}/#{locale}`.split

        screenshots = list.map do |screen|
          next if screen.match(device).nil?
          "#{path}/#{locale}#{screen}" unless Dir.exists?("#{path}/#{locale}#{screen}")    
        end.compact
      end

      def self.upload_on_appaloosa api_key, store_id, binary_path, screenshots, group_ids
        screenshots = set_all_screenshots_links screenshots
        binding.pry
        response = HTTP.post("#{APPALOOSA_SERVER}/#{store_id}/applications/upload",
          json: { store_id: store_id , 
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

      def self.set_all_screenshots_links screenshots
        if screenshots == nil
          screens = %w(screenshot1 screenshot2 screenshot3 screenshot4 screenshot5)
          screenshots = screens.map do |k, v|
            v = ''
          end
        else
          missings = 5 - screenshots.count
          (1..missings).map do |i|
            screenshots << ""
          end
        end
        screenshots     
      end

      def self.get_s3_url api_key, store_id, path
        binary_path = HTTP.get("#{APPALOOSA_SERVER}/#{store_id}/bitrise_binaries/url_for_download", json: { "store_id": store_id , "api_key": api_key, key: path })
        json_res = JSON.parse binary_path
        return if error_detected json_res['errors']
        binary_path = json_res['binary_url']
      end

      def self.upload_on_s3 file
        file_name = file.split('/').last
        response = HTTP.get("#{APPALOOSA_SERVER}/bitrise_binaries/fastlane", :json =>  { file: file_name })       
        json_res = JSON.parse response
        url =  json_res['s3_sign']
        path =  json_res['path']
        uri = URI.parse(Base64.decode64(url))

        File.open(file, 'rb') do |f|
          Net::HTTP.start(uri.host) do |http|
            http.send_request("PUT", uri.request_uri, f.read, {
              "content-type" => "",
            })
          end
        end
        path
      end
      
      def self.get_env_value option
        self.available_options.map do |opt|
          if opt.key == option.to_sym
            opt
          end
        end.compact[0].default_value
      end

      def self.error_detected errors
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
        "Upload your app to Appaloosa Store"
      end

      def self.details
        # Optional:
        # this is your change to provide a more detailed description of this action
        "You can use this action to do cool things..."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :binary,
                                     env_name: "FL_APPALOOSA_BINARY", # The name of the environment variable
                                     description: "Path to your IPA file. Optional if you use the `ipa` or `xcodebuild` action. For Mac zip the .app",
                                       default_value: Actions.lane_context[SharedValues::IPA_OUTPUT_PATH],
                                       verify_block: proc do |value|
                                         raise "Couldn't find ipa file at path '#{value}'".red unless File.exist?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :api_token,
                                       env_name: "FL_APPALOOSA_API_TOKEN", # The name of the environment variable
                                       description: "Your API Token, if you don\'t have an account hit [enter]", # a short description of this parameter
                                       verify_block: proc do |value|
                                       end),
          FastlaneCore::ConfigItem.new(key: :store_id,
                                       env_name: "FL_APPALOOSA_STORE_ID", # The name of the environment variable
                                       description: "Your Store id, if you don\'t have an account hit [enter]", # a short description of this parameter
                                       verify_block: proc do |value|
                                       end),
          FastlaneCore::ConfigItem.new(key: :email,
                                     env_name: "FL_APPALOOSA_EMAIL", # The name of the environment variable
                                     description: "It's your first time? Give your email address", # a short description of this parameter
                                     optional: true),
          FastlaneCore::ConfigItem.new(key: :group_ids,
                                     env_name: "FL_APPALOOSA_GROUPS", # The name of the environment variable
                                     description: "Your app is limited to special users? Give us the group ids", # a short description of this parameter
                                     default_value: '',
                                     optional: true),
          FastlaneCore::ConfigItem.new(key: :screenshots,
                                     env_name: "FL_APPALOOSA_SCREENSHOTS", # The name of the environment variable
                                     description: "Add some screenshots application to your store or hit [enter]", # a short description of this parameter
                                     default_value: Actions.lane_context[SharedValues::SNAPSHOT_SCREENSHOTS_PATH]),
          FastlaneCore::ConfigItem.new(key: :language,
                                      env_name: "FL_APPALOOSA_LOCALE", # The name of the environment variable
                                      description: "Select the folder locale for yours screenshots", # a short description of this parameter
                                      default_value: 'en-US',
                                      optional: true
                                     ),
          FastlaneCore::ConfigItem.new(key: :device,
                                      env_name: "FL_APPALOOSA_DEVICE", # The name of the environment variable
                                      description: "Select the device format for yours screenshots", # a short description of this parameter
                                      optional: true
                                     ),
          FastlaneCore::ConfigItem.new(key: :development,
                                       env_name: "FL_APPALOOSA_DEVELOPMENT",
                                       description: "Create a development certificate instead of a distribution one",
                                       is_string: false, # true: verifies the input is a string, false: every kind of value
                                       default_value: false,
                                       optional: true) # the default value if the user didn't provide one
        ]
      end

      def self.authors
        ["Appaloosa"]
      end

      def self.is_supported?(platform)
        platform == :ios
      end
    end
  end
end
