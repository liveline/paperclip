module Paperclip
  class Attachment
    attr_accessor :name, :options, :model, :storage

    def initialize(name, model, options = Options.new)
      @name = name
      @model = model
      @options = options
      @storage = Storage.for(@options.storage[:backend])
      @storage.attachment = self
      @files_to_save   = {}
      @files_to_delete = []
      set_existing_paths
    end

    def assign(file)
      self.clear
      return if file.nil?

      write_model_attribute(:file_name,    File.basename(file.original_filename))
      write_model_attribute(:content_type, file.content_type)
      write_model_attribute(:file_size,    file.size)

      @files_to_save = process(file)
    end

    def present?
      not file_name.nil?
    end

    def file_name
      read_model_attribute(:file_name)
    end

    def content_type
      read_model_attribute(:content_type)
    end

    def file_size
      read_model_attribute(:file_size)
    end

    def default_style
      options.default_style
    end

    def path(style = default_style)
      Paperclip::Interpolations.interpolate(options.path, self, style)
    end

    def url(style = default_style)
      if present?
        Paperclip::Interpolations.interpolate(options.url, self, style)
      else
        Paperclip::Interpolations.interpolate(options.default_url, self, style)
      end
    end

    def clear
      @files_to_save.clear
      if present?
        @files_to_delete = options.styles.keys.map{|key| path(key) }
      end
      write_model_attribute(:file_name,    nil)
      write_model_attribute(:content_type, nil)
      write_model_attribute(:file_size,    nil)
    end

    def commit
      flush_renames
      flush_writes
      flush_deletes
      set_existing_paths
    end

    private

    def process(original_file)
      return unless callback(:"before_#{name}_process")
      files = {}

      options.styles.keys.each do |style|
        style_options = options.styles[style].dup
        files[style]  = process_file(original_file, style, style_options)
      end 
      
      return unless callback(:"after_#{name}_process")
      files
    end

    def process_file(original_file, style, style_options)
      return unless callback(:"before_#{name}_#{style}_process")

      processors = style_options.delete(:processors)
      files = processors.inject(original_file) do |file, name|
        Processor.for(name).make(file, style_options, self)
      end
      
      return unless callback(:"after_#{name}_#{style}_process")
      files
    end

    def callback(callback_name)
      if model.respond_to?(callback_name)
        model.send(callback_name, model) != false
      else
        true
      end
    end

    def read_model_attribute(attribute)
      @model.send(:"#{name}_#{attribute}")
    end

    def write_model_attribute(attribute, data)
      @model.send(:"#{name}_#{attribute}=", data)
    end

    def set_existing_paths
      @existing_paths = {}
      return unless present?
      @existing_paths = options.styles.keys.inject({}) do |hash, key|
        hash[key] = path(key)
        hash
      end
    end

    def flush_writes
      @files_to_save.each do |style, file|
        storage.write(path(style), file)
      end
      @files_to_save.clear
    end

    def flush_deletes
      @files_to_delete.each do |path|
        storage.delete(path)
      end
      @files_to_delete.clear
    end

    def flush_renames
      return unless present?
      @existing_paths.each do |style, existing_path|
        storage.rename(existing_path, path(style))
      end
    end
  end
end
