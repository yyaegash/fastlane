require "http"
require "base64"
require 'pry'

APPALOOSA_SERVER = "http://lvh.me:3000/api/v1"
BINARY = 1
SCREENSHOTS = 2

module Fastlane
  module Actions
    module SharedValues
    end

    class AppaloosaAction < Action
      def self.run(params)
        api_key = params[:api_token]
        store_id = params[:store_id]
        email = api_key.size == 0 && store_id.size == 0
        bin = params[:binary]
        bin = bin.gsub(' ', '')
        `mv *.ipa #{bin}`
        if email
          response = HTTP.post("#{APPALOOSA_SERVER}/bitrise_binaries/create_an_account", :form => {:email => "#{params[:email]}"})
          json_res = JSON.parse response
          api_key = json_res['api_key']
          store_id = json_res['store_id']
          return if print_errors json_res['errors']
        elsif params[:api_token].size == 0 && params[:store_id].size == 0
          return if print_errors 'Missing authentification values'
        end
        `rm fastlane/screenshots/screenshots.html`

        params[:screenshots]

        screenshots = params[:screenshots].strip.size > 0 ? screenshots_list(params[:screenshots]) : nil

        unless screenshots.nil?
          binding.pry
          list = []
          list << screenshots.map do |screen|
            upload_on_s3 screen, SCREENSHOTS
          end
          urls = []
          urls << list.flatten.map do |url|
            get_s3_url api_key, store_id, url
          end
        end
        urls = urls.is_a?(Array) ? urls.flatten : nil
        key = upload_on_s3 bin, BINARY
        binary_path = get_s3_url api_key, store_id, key
        upload_on_appaloosa api_key, store_id, binary_path, urls
        `mv #{bin} #{params[:binary]}`
        `rm #{bin}`
      end

      def self.screenshots_list path
        list_screenshots = `ls #{path}/en-US/`

        list = list_screenshots.split
        
        screenshots = list.map do |screen|
          "./fastlane/screenshots/en-US/#{screen}"
        end
      end

      def self.upload_on_appaloosa api_key, store_id, binary_path, screenshots=nil
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
        response = HTTP.post("#{APPALOOSA_SERVER}/#{store_id}/applications/upload", json: { "store_id": store_id , "api_key": api_key, application: { binary_path: binary_path, screenshot1: screenshots[0], screenshot2: screenshots[1], screenshot3: screenshots[2], screenshot4: screenshots[3], screenshot5: screenshots[4] } })
        json_res = JSON.parse response
        puts json_res
      end

      def self.get_s3_url api_key, store_id, path
        binary_path = HTTP.get("#{APPALOOSA_SERVER}/#{store_id}/bitrise_binaries/url_for_download", json: { "store_id": store_id , "api_key": api_key, key: path })
        json_res = JSON.parse binary_path
        return if print_errors json_res['errors']
        binary_path = json_res['binary_url']
      end

      def self.upload_on_s3 file, type
        file_name = file.split('/').last
        if type == BINARY
          response = HTTP.get("#{APPALOOSA_SERVER}/bitrise_binaries/fastlane", :json =>  { binary: file_name })
        elsif type == SCREENSHOTS
          response = HTTP.get("#{APPALOOSA_SERVER}/bitrise_binaries/fastlane", :json =>  { screenshot: file_name })
        end          
        json_res =  JSON.parse response
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

      def self.print_errors errors
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
        # Define all options your action supports. 
        
        # Below a few examples
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
                                          # raise "No API token for AppaloosaAction given, pass using `api_token: 'token'`".red unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :store_id,
                                       env_name: "FL_APPALOOSA_STORE_ID", # The name of the environment variable
                                       description: "Your Store id, if you don\'t have an account hit [enter]", # a short description of this parameter
                                       verify_block: proc do |value|
                                          # raise "No Store id token for AppaloosaAction given, pass using `store_id: 'token'`".red unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :email,
                                     env_name: "FL_APPALOOSA_EMAIL", # The name of the environment variable
                                     description: "It's your first time? Give your email address", # a short description of this parameter
                                     optional: true),
          FastlaneCore::ConfigItem.new(key: :group_ids,
                                     env_name: "FL_APPALOOSA_GROUPS", # The name of the environment variable
                                     description: "You want publish your app for restricted user? Let there user group ids", # a short description of this parameter
                                     optional: true),
          FastlaneCore::ConfigItem.new(key: :screenshots,
                                     env_name: "FL_APPALOOSA_SCREENSHOTS", # The name of the environment variable
                                     description: "Add some screenshots application in your store", # a short description of this parameter
                                     default_value: Actions.lane_context[SharedValues::SNAPSHOT_SCREENSHOTS_PATH]),
          FastlaneCore::ConfigItem.new(key: :development,
                                       env_name: "FL_APPALOOSA_DEVELOPMENT",
                                       description: "Create a development certificate instead of a distribution one",
                                       is_string: false, # true: verifies the input is a string, false: every kind of value
                                       default_value: false,
                                       optional: true) # the default value if the user didn't provide one
        ]
      end

      def self.output
      end

      def self.return_value
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
