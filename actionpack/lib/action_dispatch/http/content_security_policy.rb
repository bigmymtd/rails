# frozen_string_literal: true

module ActionDispatch #:nodoc:
  class ContentSecurityPolicy
    class Middleware
      CONTENT_TYPE = "Content-Type".freeze
      POLICY = "Content-Security-Policy".freeze
      POLICY_REPORT_ONLY = "Content-Security-Policy-Report-Only".freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new env
        _, headers, _ = response = @app.call(env)

        return response unless html_response?(headers)
        return response if policy_present?(headers)

        if policy = request.content_security_policy
          headers[header_name(request)] = policy.build(request.controller_instance)
        end

        response
      end

      private

        def html_response?(headers)
          if content_type = headers[CONTENT_TYPE]
            content_type =~ /html/
          end
        end

        def header_name(request)
          if request.content_security_policy_report_only
            POLICY_REPORT_ONLY
          else
            POLICY
          end
        end

        def policy_present?(headers)
          headers[POLICY] || headers[POLICY_REPORT_ONLY]
        end
    end

    module Request
      POLICY = "action_dispatch.content_security_policy".freeze
      POLICY_REPORT_ONLY = "action_dispatch.content_security_policy_report_only".freeze

      def content_security_policy
        get_header(POLICY)
      end

      def content_security_policy=(policy)
        set_header(POLICY, policy)
      end

      def content_security_policy_report_only
        get_header(POLICY_REPORT_ONLY)
      end

      def content_security_policy_report_only=(value)
        set_header(POLICY_REPORT_ONLY, value)
      end
    end

    MAPPINGS = {
      self:           "'self'",
      unsafe_eval:    "'unsafe-eval'",
      unsafe_inline:  "'unsafe-inline'",
      none:           "'none'",
      http:           "http:",
      https:          "https:",
      data:           "data:",
      mediastream:    "mediastream:",
      blob:           "blob:",
      filesystem:     "filesystem:",
      report_sample:  "'report-sample'",
      strict_dynamic: "'strict-dynamic'"
    }.freeze

    DIRECTIVES = {
      base_uri:        "base-uri",
      child_src:       "child-src",
      connect_src:     "connect-src",
      default_src:     "default-src",
      font_src:        "font-src",
      form_action:     "form-action",
      frame_ancestors: "frame-ancestors",
      frame_src:       "frame-src",
      img_src:         "img-src",
      manifest_src:    "manifest-src",
      media_src:       "media-src",
      object_src:      "object-src",
      script_src:      "script-src",
      style_src:       "style-src",
      worker_src:      "worker-src"
    }.freeze

    private_constant :MAPPINGS, :DIRECTIVES

    attr_reader :directives

    def initialize
      @directives = {}
      yield self if block_given?
    end

    def initialize_copy(other)
      @directives = other.directives.deep_dup
    end

    DIRECTIVES.each do |name, directive|
      define_method(name) do |*sources|
        if sources.first
          @directives[directive] = apply_mappings(sources)
        else
          @directives.delete(directive)
        end
      end
    end

    def block_all_mixed_content(enabled = true)
      if enabled
        @directives["block-all-mixed-content"] = true
      else
        @directives.delete("block-all-mixed-content")
      end
    end

    def plugin_types(*types)
      if types.first
        @directives["plugin-types"] = types
      else
        @directives.delete("plugin-types")
      end
    end

    def report_uri(uri)
      @directives["report-uri"] = [uri]
    end

    def require_sri_for(*types)
      if types.first
        @directives["require-sri-for"] = types
      else
        @directives.delete("require-sri-for")
      end
    end

    def sandbox(*values)
      if values.empty?
        @directives["sandbox"] = true
      elsif values.first
        @directives["sandbox"] = values
      else
        @directives.delete("sandbox")
      end
    end

    def upgrade_insecure_requests(enabled = true)
      if enabled
        @directives["upgrade-insecure-requests"] = true
      else
        @directives.delete("upgrade-insecure-requests")
      end
    end

    def build(context = nil)
      build_directives(context).compact.join("; ") + ";"
    end

    private
      def apply_mappings(sources)
        sources.map do |source|
          case source
          when Symbol
            apply_mapping(source)
          when String, Proc
            source
          else
            raise ArgumentError, "Invalid content security policy source: #{source.inspect}"
          end
        end
      end

      def apply_mapping(source)
        MAPPINGS.fetch(source) do
          raise ArgumentError, "Unknown content security policy source mapping: #{source.inspect}"
        end
      end

      def build_directives(context)
        @directives.map do |directive, sources|
          if sources.is_a?(Array)
            "#{directive} #{build_directive(sources, context).join(' ')}"
          elsif sources
            directive
          else
            nil
          end
        end
      end

      def build_directive(sources, context)
        sources.map { |source| resolve_source(source, context) }
      end

      def resolve_source(source, context)
        case source
        when String
          source
        when Symbol
          source.to_s
        when Proc
          if context.nil?
            raise RuntimeError, "Missing context for the dynamic content security policy source: #{source.inspect}"
          else
            context.instance_exec(&source)
          end
        else
          raise RuntimeError, "Unexpected content security policy source: #{source.inspect}"
        end
      end
  end
end
