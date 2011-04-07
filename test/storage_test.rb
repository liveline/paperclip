require './test/helper'
require 'aws/s3'

class StorageTest < Test::Unit::TestCase
  def rails_env(env)
    silence_warnings do
      Object.const_set(:Rails, stub('Rails', :env => env))
    end
  end

  context "filesystem" do
    setup do
      rebuild_model :styles => { :thumbnail => "25x25#" }
      @dummy = Dummy.create!

      @dummy.avatar = File.open(File.join(File.dirname(__FILE__), "fixtures", "5k.png"))
    end

    should "allow file assignment" do
      assert @dummy.save
    end

    should "store the original" do
      @dummy.save
      assert File.exists?(@dummy.avatar.path)
    end

    should "store the thumbnail" do
      @dummy.save
      assert File.exists?(@dummy.avatar.path(:thumbnail))
    end
  end

  context "Parsing S3 config" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
      rebuild_model :storage => :s3,
                    :bucket => "testing",
                    :s3_credentials => {:not => :important}

      @dummy = Dummy.new
      @avatar = @dummy.avatar
    end

    should "get the correct config when RAILS_ENV is production" do
      rails_env("production")
      assert_equal({:key => "12345"},
                   @avatar.parse_config('production' => {:key => '12345'},
                                             :development => {:key => "54321"}))
    end

    should "get the correct config when RAILS_ENV is development" do
      rails_env("development")
      assert_equal({:key => "54321"},
                   @avatar.parse_config('production' => {:key => '12345'},
                                             :development => {:key => "54321"}))
    end

    should "return the argument if the key does not exist" do
      rails_env("not really an env")
      assert_equal({:test => "12345"}, @avatar.parse_config(:test => "12345"))
    end
  end

  context "When locating which config to use" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
    end

    context "if only :s3_config is supplied" do
      setup do
        rebuild_class :storage => :s3,
                      :s3_config => {:bucket => 's3_config'}
        @dummy = Dummy.new
      end

      should "use :s3_config for configuration" do
        assert_equal "s3_config", @dummy.avatar.bucket_name
      end
    end

    context "if only :s3_credentials is supplied" do
      setup do
        rebuild_class :storage => :s3,
                      :s3_credentials => {:bucket => 's3_credentials'}
        @dummy = Dummy.new
      end

      should "use :s3_credentials for configuration" do
        assert_equal "s3_credentials", @dummy.avatar.bucket_name
      end
    end

    context "if both :s3_config and :s3_credentials are supplied" do
      setup do
        rebuild_class :storage => :s3,
                      :s3_config => {:bucket => 's3_config'},
                      :s3_credentials => {:bucket => 's3_credentials'}
        @dummy = Dummy.new
      end

      should "use :s3_config for configuration" do
        assert_equal "s3_config", @dummy.avatar.bucket_name
      end
    end
  end

  context "" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
      rebuild_model :storage => :s3,
                    :s3_credentials => {},
                    :bucket => "bucket",
                    :path => ":attachment/:basename.:extension",
                    :url => ":s3_path_url"
      @dummy = Dummy.new
      @dummy.avatar = StringIO.new(".")
    end

    should "return a url based on an S3 path" do
      assert_match %r{^http://s3.amazonaws.com/bucket/avatars/stringio.txt}, @dummy.avatar.url
    end
  end
  context "" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
      rebuild_model :storage => :s3,
                    :s3_credentials => {},
                    :bucket => "bucket",
                    :path => ":attachment/:basename.:extension",
                    :url => ":s3_domain_url"
      @dummy = Dummy.new
      @dummy.avatar = StringIO.new(".")
    end

    should "return a url based on an S3 subdomain" do
      assert_match %r{^http://bucket.s3.amazonaws.com/avatars/stringio.txt}, @dummy.avatar.url
    end
  end
  context "" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
      rebuild_model :storage => :s3,
                    :s3_credentials => {
                      :production   => { :bucket => "prod_bucket" },
                      :development  => { :bucket => "dev_bucket" }
                    },
                    :s3_host_alias => "something.something.com",
                    :path => ":attachment/:basename.:extension",
                    :url => ":s3_alias_url"
      @dummy = Dummy.new
      @dummy.avatar = StringIO.new(".")
    end

    should "return a url based on the host_alias" do
      assert_match %r{^http://something.something.com/avatars/stringio.txt}, @dummy.avatar.url
    end
  end

  context "Generating a url with an expiration" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
      rebuild_model :storage => :s3,
                    :s3_credentials => {
                      :production   => { :bucket => "prod_bucket" },
                      :development  => { :bucket => "dev_bucket" }
                    },
                    :s3_host_alias => "something.something.com",
                    :path => ":attachment/:basename.:extension",
                    :url => ":s3_alias_url"

      rails_env("production")

      @dummy = Dummy.new
      @dummy.avatar = StringIO.new(".")

      AWS::S3::S3Object.expects(:url_for).with("avatars/stringio.txt", "prod_bucket", { :expires_in => 3600 })

      @dummy.avatar.expiring_url
    end

    should "should succeed" do
      assert true
    end
  end

  context "Parsing S3 credentials with a bucket in them" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
      rebuild_model :storage => :s3,
                    :s3_credentials => {
                      :production   => { :bucket => "prod_bucket" },
                      :development  => { :bucket => "dev_bucket" }
                    }
      @dummy = Dummy.new
    end

    should "get the right bucket in production" do
      rails_env("production")
      assert_equal "prod_bucket", @dummy.avatar.bucket_name
    end

    should "get the right bucket in development" do
      rails_env("development")
      assert_equal "dev_bucket", @dummy.avatar.bucket_name
    end
  end

  context "An attachment with S3 storage" do
    setup do
      rebuild_model :storage => :s3,
                    :bucket => "testing",
                    :path => ":attachment/:style/:basename.:extension",
                    :s3_credentials => {
                      'access_key_id' => "12345",
                      'secret_access_key' => "54321"
                    }
    end

    should "be extended by the S3 module" do
      assert Dummy.new.avatar.is_a?(Paperclip::Storage::S3)
    end

    should "not be extended by the Filesystem module" do
      assert ! Dummy.new.avatar.is_a?(Paperclip::Storage::Filesystem)
    end

    context "when assigned" do
      setup do
        @file = File.new(File.join(File.dirname(__FILE__), 'fixtures', '5k.png'), 'rb')
        @dummy = Dummy.new
        @dummy.avatar = @file
      end

      teardown { @file.close }

      should "not get a bucket to get a URL" do
        @dummy.avatar.expects(:s3).never
        @dummy.avatar.expects(:s3_bucket).never
        assert_match %r{^http://s3\.amazonaws\.com/testing/avatars/original/5k\.png}, @dummy.avatar.url
      end

      context "and saved" do
        setup do
          AWS::S3::S3Object.stubs(:store).with(@dummy.avatar.path, anything, 'testing', :content_type => 'image/png', :access => :public_read)
          @dummy.save
        end

        should "succeed" do
          assert true
        end
      end

      context "and saved without a bucket" do
        setup do
          class AWS::S3::NoSuchBucket < AWS::S3::ResponseError
            # Force the class to be created as a proper subclass of ResponseError thanks to AWS::S3's autocreation of exceptions
          end
          AWS::S3::Bucket.expects(:create).with("testing")
          AWS::S3::S3Object.stubs(:store).raises(AWS::S3::NoSuchBucket.new(:message, :response)).then.returns(true)
          @dummy.save
        end

        should "succeed" do
          assert true
        end
      end

      context "and remove" do
        setup do
          AWS::S3::S3Object.stubs(:exists?).returns(true)
          AWS::S3::S3Object.stubs(:delete)
          @dummy.destroy_attached_files
        end

        should "succeed" do
          assert true
        end
      end
    end
  end

  context "An attachment with S3 storage and bucket defined as a Proc" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
      rebuild_model :storage => :s3,
                    :bucket => lambda { |attachment| "bucket_#{attachment.instance.other}" },
                    :s3_credentials => {:not => :important}
    end

    should "get the right bucket name" do
      assert "bucket_a", Dummy.new(:other => 'a').avatar.bucket_name
      assert "bucket_b", Dummy.new(:other => 'b').avatar.bucket_name
    end
  end

  context "An attachment with S3 storage and specific s3 headers set" do
    setup do
      AWS::S3::Base.stubs(:establish_connection!)
      rebuild_model :storage => :s3,
                    :bucket => "testing",
                    :path => ":attachment/:style/:basename.:extension",
                    :s3_credentials => {
                      'access_key_id' => "12345",
                      'secret_access_key' => "54321"
                    },
                    :s3_headers => {'Cache-Control' => 'max-age=31557600'}
    end

    context "when assigned" do
      setup do
        @file = File.new(File.join(File.dirname(__FILE__), 'fixtures', '5k.png'), 'rb')
        @dummy = Dummy.new
        @dummy.avatar = @file
      end

      teardown { @file.close }

      context "and saved" do
        setup do
          AWS::S3::Base.stubs(:establish_connection!)
          AWS::S3::S3Object.stubs(:store).with(@dummy.avatar.path,
                                               anything,
                                               'testing',
                                               :content_type => 'image/png',
                                               :access => :public_read,
                                               'Cache-Control' => 'max-age=31557600')
          @dummy.save
        end

        should "succeed" do
          assert true
        end
      end
    end
  end

  context "with S3 credentials supplied as Pathname" do
     setup do
       ENV['S3_KEY']    = 'pathname_key'
       ENV['S3_BUCKET'] = 'pathname_bucket'
       ENV['S3_SECRET'] = 'pathname_secret'

       rails_env('test')

       rebuild_model :storage        => :s3,
                     :s3_credentials => Pathname.new(File.join(File.dirname(__FILE__))).join("fixtures/s3.yml")

       Dummy.delete_all
       @dummy = Dummy.new
     end

     should "parse the credentials" do
       assert_equal 'pathname_bucket', @dummy.avatar.bucket_name
       assert_equal 'pathname_key', AWS::S3::Base.connection.options[:access_key_id]
       assert_equal 'pathname_secret', AWS::S3::Base.connection.options[:secret_access_key]
     end
  end

  context "with S3 credentials in a YAML file" do
    setup do
      ENV['S3_KEY']         = 'env_key'
      ENV['S3_BUCKET']      = 'env_bucket'
      ENV['S3_SECRET']      = 'env_secret'
      ENV['S3_PERMISSIONS'] = 'env_permissions'
      ENV['S3_PROTOCOL']    = 'env_protocol'
      ENV['S3_HOST_ALIAS']  = 'env_host_alias'

      rails_env('test')

      rebuild_model :storage        => :s3,
                    :s3_credentials => File.new(File.join(File.dirname(__FILE__), "fixtures/s3.yml"))

      Dummy.delete_all

      @dummy = Dummy.new
      @avatar = @dummy.avatar
    end

    should "run the file through ERB" do
      assert_equal 'env_bucket', @dummy.avatar.bucket_name
      assert_equal 'env_key', AWS::S3::Base.connection.options[:access_key_id]
      assert_equal 'env_secret', AWS::S3::Base.connection.options[:secret_access_key]
      assert_equal 'test.example.com', AWS::S3::Base.connection.options[:server]
      assert_equal 'env_permissions', @dummy.avatar.instance_variable_get('@s3_permissions')
      assert_equal 'env_protocol', @dummy.avatar.s3_protocol
      assert_equal 'env_host_alias', @dummy.avatar.s3_host_alias
    end
  end

  unless ENV["S3_TEST_BUCKET"].blank?
    context "Using S3 for real, an attachment with S3 storage" do
      setup do
        rebuild_model :styles => { :thumb => "100x100", :square => "32x32#" },
                      :storage => :s3,
                      :bucket => ENV["S3_TEST_BUCKET"],
                      :path => ":class/:attachment/:id/:style.:extension",
                      :s3_credentials => File.new(File.join(File.dirname(__FILE__), "s3.yml"))

        Dummy.delete_all
        @dummy = Dummy.new
      end

      should "be extended by the S3 module" do
        assert Dummy.new.avatar.is_a?(Paperclip::Storage::S3)
      end

      context "when assigned" do
        setup do
          @file = File.new(File.join(File.dirname(__FILE__), 'fixtures', '5k.png'), 'rb')
          @dummy.avatar = @file
        end

        teardown { @file.close }

        should "still return a Tempfile when sent #to_file" do
          assert_equal Paperclip::Tempfile, @dummy.avatar.to_file.class
        end

        context "and saved" do
          setup do
            @dummy.save
          end

          should "be on S3" do
            assert true
          end

          should "generate a tempfile with the right name" do
            file = @dummy.avatar.to_file
            assert_match /^original.*\.png$/, File.basename(file.path)
          end
        end
      end
    end
  end
end
