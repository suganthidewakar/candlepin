require 'candlepin_api'
require 'pp'
require 'zip/zip'

# Provides initialization and cleanup of data that was used in the scenario
shared_examples_for 'Candlepin Scenarios' do

  before do
    @cp = Candlepin.new('admin', 'admin')
    @owners = []
    @products = []
  end

  after do
    @owners.reverse_each { |owner| @cp.delete_owner owner.key }

    # TODO:  delete products?
  end
end

module CandlepinMethods

  # Wrapper for ruby API so we can track all owners we created and clean them
  # up. Note that this entails cleanup of all objects beneath that owner, so
  # most other objects can be created using the ruby API.
  def create_owner(owner_name, parent=nil)
    owner = @cp.create_owner(owner_name, parent)
    @owners << owner

    return owner
  end

  # Wrapper for the ruby API's create product. Products do not get cleaned
  # up when an owner is deleted so we will need to track them.
  def create_product(id=nil, name=nil, params={})
    # For purposes of testing, you can omit id and name to create with
    # random strings.
    id = "#{rand(100000)}" #id has to be a number. OID encoding fails otherwise
    name ||= random_string('testproduct')
    product = @cp.create_product(id, name, params)
    return product
  end

  def create_content(params={})
    random_str = rand(1000000)
    modified_products = params[:modified_products] || []
    @cp.create_content(random_str, random_str, random_str, "yum",
      random_str, random_str, random_str, modified_products)
  end

  def user_client(owner, user_name)
    @cp.create_user(owner.key, user_name, 'password')
    Candlepin.new(user_name, 'password')
  end

  def consumer_client(cp_client, consumer_name, type=:system, username=nil, facts= {})
    consumer = cp_client.register(consumer_name, type, nil, facts, username)
    Candlepin.new(nil, nil, consumer.idCert.cert, consumer.idCert.key)
  end

  def trusted_consumer_client(uuid)
    Candlepin.new(nil, nil, nil, nil, "localhost", "8443", nil, uuid)
  end  

  def random_string(prefix=nil)
    prefix ||= ''
    "#{prefix}-#{rand(100000)}"
  end

  def check_for_hateoas(json)
    json.keys.length.should == 2
    json.has_key?('href').should be_true
    json.has_key?('id').should be_true
  end

  # TODO:  This might be better if it were added to
  # the OpenSSL::X509::Certificate class
  def get_extension(cert, oid)
    extension = cert.extensions.select { |ext| ext.oid == oid }[0]

    return nil if extension.nil?

    value = extension.value
    # Weird ssl cert issue - have to strip the leading dots:
    value = value[2..-1] if value.match(/^\.\./)

    return value
  end

  # ent_cert here is the JSON representation:
  def verify_cert_dates(ent_cert, end_date, flex_days)
    ent_cert.entitlement.flexExpiryDays.should == flex_days

    cert = OpenSSL::X509::Certificate.new(ent_cert.cert)

    # Check the entitlement end date:
    cert_end_date = cert.not_after
    flex_end_date = end_date + flex_days
    cert_end_date.year.should == flex_end_date.year
    cert_end_date.month.should == flex_end_date.month
    cert_end_date.day.should == flex_end_date.day

    # Check the order namespace end date, this one should not have changed:
    order_end_date = Date.strptime(get_extension(cert,
        "1.3.6.1.4.1.2312.9.4.7"))
    order_end_date.year.should == end_date.year
    order_end_date.month.should == end_date.month
    order_end_date.day.should == end_date.day
  end

end

module ExportMethods

  def create_candlepin_export
    # WARNING: Creating export is fairly expensive, so using a before all to
    # create one and use it for all tests. Because before(:all) runs before
    # any before(:each), we cannot use the normal helper methods. :( As such,
    # creating one owner, and cleaning it up manually:
    @cp = Candlepin.new('admin', 'admin')
    @owner = @cp.create_owner(random_string('test_owner'))

    owner_client = user_client(@owner, random_string('testuser'))
    @flex_days = 30
    product1 = create_product(random_string(), random_string(),
        {:attributes => {"flex_expiry" => @flex_days.to_s}})
    product2 = create_product()
    @end_date = Date.new(2025, 5, 29)

    sub1 = @cp.create_subscription(@owner.key, product1.id, 2, [], '', '12345', nil, @end_date)
    sub2 = @cp.create_subscription(@owner.key, product2.id, 4, [], '', '12345', nil, @end_date)
    @cp.refresh_pools(@owner.key)

    pool1 = @cp.list_pools(:owner => @owner.id, :product => product1.id)[0]
    pool2 = @cp.list_pools(:owner => @owner.id, :product => product2.id)[0]

    @candlepin_client = consumer_client(owner_client, random_string(),
        "candlepin")
    @flex_entitlement = @candlepin_client.consume_pool(pool1.id)[0]
    @candlepin_client.consume_pool(pool2.id)

    # Make a temporary directory where we can safely extract our archive:
    @tmp_dir = File.join(Dir.tmpdir, random_string('candlepin-rspec'))
    @export_dir = File.join(@tmp_dir, "export")
    Dir.mkdir(@tmp_dir)

    @export_filename = @candlepin_client.export_consumer(@tmp_dir)
    # Save current working dir so we can return later:
    @orig_working_dir = Dir.pwd()

    puts "---" + @export_filename
    File.exist?(@export_filename).should == true
    unzip_export_file(@export_filename, @tmp_dir)
    unzip_export_file(File.join(@tmp_dir, "consumer_export.zip"), @tmp_dir)
  end

  def cleanup_candlepin_export
    Dir.chdir(@orig_working_dir)

    FileUtils.rm_rf(@tmp_dir)
    @cp.delete_owner(@owner.key)
  end

  def unzip_export_file(filename, dest_dir)
    Zip::ZipFile::open(filename) do |zf|
       zf.each do |e|
         fpath = File.join(dest_dir, e.name)
         FileUtils.mkdir_p(File.dirname(fpath))
         zf.extract(e, fpath)
       end
    end
    filename.split('.zip')[0]
  end

  def parse_file(filename)
    JSON.parse(load_file(filename))
  end

  def load_file(filename)
    contents = ''
    f = File.open(filename, "r")
    f.each_line do |line|
      contents += line
    end
    return contents
  end

  def files_in_dir(dir_name)
    Dir.entries(dir_name).select {|e| e != '.' and e != '..' }
  end

end


# This allows for dot notation instead of using hashes for everything
class Hash

  # Not sure if this is a great idea
  # Override Ruby's id method to access our id attribute
  def id
    self['id']
  end

  def method_missing(method, *args)
    if ((method.to_s =~ /=$/) != nil)
        self[method.to_s.gsub(/=$/, '')] = args[0]
    else
        self[method.to_s]
    end
  end
end
