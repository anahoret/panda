module Kernel
  # Options
  # =======
  # * :tries  Number of retries to perform. Defaults to 1.
  #           Note this means it actually tries 2 times!
  # * :on -   The Exception on which a retry will be performed. Defaults to 
  #           Exception, which retries on any Exception.
  # * :delay - Delay in seconds before the next try (optional)
  #
  # Example
  # =======
  #   retryable(:tries => 1, :on => OpenURI::HTTPError) do
  #     # your code here
  #   end
  #
  def retryable(options = {}, &block)
    opts = { :tries => 1, :on => Exception }.merge(options)

    retry_exception, retries, delay = opts[:on], opts[:tries], opts[:delay]

    begin
      return yield
    rescue retry_exception
      sleep delay unless delay.nil?
      retry if (retries -= 1) > 0
    end

    yield
  end
end
