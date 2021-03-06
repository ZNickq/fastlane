module Spaceship
  # This class is used to upload Digital files (Images, Videos, JSON files) onto the du-itc service.
  # Its implementation is tied to the tunes module (in particular using +AppVersion+ instances)
  class DUClient < Spaceship::Client #:nodoc:
    #####################################################
    # @!group Init and Login
    #####################################################

    def self.hostname
      "https://du-itc.itunes.apple.com"
    end

    #####################################################
    # @!group Images
    #####################################################

    def upload_screenshot(app_version, upload_file, content_provider_id, sso_token_for_image, device, is_messages)
      upload_file(app_version: app_version, upload_file: upload_file, path: '/upload/image', content_provider_id: content_provider_id, sso_token: sso_token_for_image, du_validation_rule_set: screenshot_picture_type(device, is_messages))
    end

    def upload_purchase_review_screenshot(app_id, upload_file, content_provider_id, sso_token_for_image)
      upload_file(app_id: app_id, upload_file: upload_file, path: '/upload/image', content_provider_id: content_provider_id, sso_token: sso_token_for_image, du_validation_rule_set: 'MZPFT.SortedScreenShot')
    end

    def upload_large_icon(app_version, upload_file, content_provider_id, sso_token_for_image)
      upload_file(app_version: app_version, upload_file: upload_file, path: '/upload/image', content_provider_id: content_provider_id, sso_token: sso_token_for_image, du_validation_rule_set: 'MZPFT.LargeApplicationIcon')
    end

    def upload_watch_icon(app_version, upload_file, content_provider_id, sso_token_for_image)
      upload_file(app_version: app_version, upload_file: upload_file, path: '/upload/image', content_provider_id: content_provider_id, sso_token: sso_token_for_image, du_validation_rule_set: 'MZPFT.GizmoAppIcon')
    end

    def upload_geojson(app_version, upload_file, content_provider_id, sso_token_for_image)
      upload_file(app_version: app_version, upload_file: upload_file, path: '/upload/geo-json', content_provider_id: content_provider_id, sso_token: sso_token_for_image)
    end

    def upload_trailer(app_version, upload_file, content_provider_id, sso_token_for_video)
      upload_file(app_version: app_version, upload_file: upload_file, path: '/upload/purple-video', content_provider_id: content_provider_id, sso_token: sso_token_for_video)
    end

    def upload_trailer_preview(app_version, upload_file, content_provider_id, sso_token_for_image, device)
      upload_file(app_version: app_version, upload_file: upload_file, path: '/upload/image', content_provider_id: content_provider_id, sso_token: sso_token_for_image, du_validation_rule_set: screenshot_picture_type(device, nil))
    end

    private

    def upload_file(app_version: nil, upload_file: nil, path: nil, content_provider_id: nil, sso_token: nil, du_validation_rule_set: nil, app_id: nil)
      raise "File #{upload_file.file_path} is empty" if upload_file.file_size == 0

      if app_id
        app_id = app_id
        app_type = nil
        version = nil
        referrer = nil
      else
        version = app_version.version
        app_id = app_version.application.apple_id
        app_type = app_version.app_type
        referrer = app_version.application.url
      end

      r = request(:post) do |req|
        req.url "#{self.class.hostname}#{path}"
        req.body = upload_file.bytes
        req.headers['Accept'] = 'application/json, text/plain, */*'
        req.headers['Content-Type'] = upload_file.content_type
        req.headers['X-Apple-Upload-Referrer'] = referrer if referrer
        req.headers['Referrer'] = referrer if referrer
        req.headers['X-Apple-Upload-AppleId'] = app_id
        req.headers['X-Apple-Jingle-Correlation-Key'] = "#{app_type}:AdamId=#{app_id}:Version=#{version}" if app_type
        req.headers['X-Apple-Upload-itctoken'] = sso_token
        req.headers['X-Apple-Upload-ContentProviderId'] = content_provider_id
        req.headers['X-Original-Filename'] = upload_file.file_name
        req.headers['X-Apple-Upload-Validation-RuleSets'] = du_validation_rule_set if du_validation_rule_set
        req.headers['Content-Length'] = upload_file.file_size.to_s
        req.headers['Connection'] = "keep-alive"
      end

      if r.status == 500 and r.body.include?("Server Error")
        return upload_file(app_version: app_version, upload_file: upload_file, path: path, content_provider_id: content_provider_id, sso_token: sso_token, du_validation_rule_set: du_validation_rule_set, app_id: app_id)
      end

      parse_upload_response(r)
    end

    # You can find this by uploading an image in iTunes connect
    # then look for the X-Apple-Upload-Validation-RuleSets value
    def picture_type_map
      # rubocop:enable Layout/ExtraSpacing
      {
        watch:        "MZPFT.SortedN27ScreenShot",
        ipad:         "MZPFT.SortedTabletScreenShot",
        ipadPro:      "MZPFT.SortedJ99ScreenShot",
        iphone6:      "MZPFT.SortedN61ScreenShot",
        iphone6Plus:  "MZPFT.SortedN56ScreenShot",
        iphone4:      "MZPFT.SortedN41ScreenShot",
        iphone35:     "MZPFT.SortedScreenShot",
        appleTV:      "MZPFT.SortedATVScreenShot",
        desktop:      "MZPFT.SortedDesktopScreenShot"
      }
    end

    def messages_picture_type_map
      # rubocop:enable Layout/ExtraSpacing
      {
        ipad:         "MZPFT.SortedTabletMessagesScreenShot",
        ipadPro:      "MZPFT.SortedJ99MessagesScreenShot",
        iphone6:      "MZPFT.SortedN61MessagesScreenShot",
        iphone6Plus:  "MZPFT.SortedN56MessagesScreenShot",
        iphone4:      "MZPFT.SortedN41MessagesScreenShot"
      }
    end

    def screenshot_picture_type(device, is_messages)
      map = is_messages ? messages_picture_type_map : picture_type_map
      device = device.to_sym
      raise "Unknown picture type for device: #{device}" unless map.key? device
      map[device]
    end

    def parse_upload_response(response)
      content = response.body
      if !content['statusCode'].nil? && content['statusCode'] != 200
        error_codes = ""
        error_codes = content['errorCodes'].join(',') unless content['errorCodes'].nil?
        error_message = "[#{error_codes}] #{content['localizedMessage']}"
        raise UnexpectedResponse.new, error_message
      end
      content
    end
  end
end
