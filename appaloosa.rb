require "http"
require "base64"

APPALOOSA_SERVER = "http://lvh.me:3000/api/v1"
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

        if email
          response = HTTP.post("#{APPALOOSA_SERVER}/bitrise_binaries/create_an_account", :form => {:email => "#{params[:email]}"})
          json_res = JSON.parse response
          api_key = json_res['api_key']
          store_id = json_res['store_id']
          return if print_errors json_res['errors']
        elsif params[:api_token].size == 0 && params[:store_id].size == 0
          return if print_errors 'Missing authentification values'
        end

        upload_on_s3 bin
        binary_path =  get_s3_url api_key, store_id
        upload_on_appaloosa api_key, store_id, binary_path
      end

      def self.upload_on_appaloosa api_key, store_id, binary_path
        response = HTTP.post("#{APPALOOSA_SERVER}/#{store_id}/applications/upload", json: { "store_id": store_id , "api_key": api_key, application: { binary_path: binary_path } })
        json_res = JSON.parse response
        puts json_res
      end

      def self.get_s3_url api_key, store_id
        path = "https://appaloosa-test.s3-eu-west-1.amazonaws.com/fastlane/474jrbq4/binary1.ipa"
        binary_path = HTTP.get("#{APPALOOSA_SERVER}/#{store_id}/bitrise_binaries/url_for_download", json: { "store_id": store_id , "api_key": api_key, key: path })
        json_res = JSON.parse binary_path
        return if print_errors json_res['errors']
        binary_path = json_res['binary_url']

      end

      def self.upload_on_s3 binary
        response = HTTP.get("#{APPALOOSA_SERVER}/bitrise_binaries/fastlane", :json =>  { binary_name: binary })
        json_res =  JSON.parse response
        url =  json_res['s3_sign']
        uri = URI.parse(Base64.decode64(url))

        File.open(binary, 'rb') do |file|
          Net::HTTP.start(uri.host) do |http|
            http.send_request("PUT", uri.request_uri, file.read, {
              "content-type" => "",
            })
          end
        end
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
          FastlaneCore::ConfigItem.new(key: :binary,
                                     env_name: "FL_APPALOOSA_BINARY", # The name of the environment variable
                                     description: "Path to your IPA file. Optional if you use the `ipa` or `xcodebuild` action. For Mac zip the .app",
                                       default_value: Actions.lane_context[SharedValues::IPA_OUTPUT_PATH],
                                       verify_block: proc do |value|
                                         raise "Couldn't find ipa file at path '#{value}'".red unless File.exist?(value)
                                       end),
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
