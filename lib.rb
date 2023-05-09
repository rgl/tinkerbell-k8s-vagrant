require 'ipaddr'
require 'open3'

def get_or_generate_k3s_token
  # TODO generate an unique random an cache it.
  # generated with openssl rand -hex 32
  '7e982a7bbac5f385ecbb988f800787bc9bb617552813a63c4469521c53d83b6e'
end

def generate_nodes(first_ip_address, count, name_prefix)
  ip_addr = IPAddr.new first_ip_address
  (1..count).map do |n|
    ip_address, ip_addr = ip_addr.to_s, ip_addr.succ
    name = "#{name_prefix}#{n}"
    fqdn = "#{name}.example.test"
    [name, fqdn, ip_address, n]
  end
end

def vbmc_domain_name(machine)
  "#{File.basename(File.dirname(__FILE__))}_#{machine.name}"
end

def vbmc_container_name(machine, bmc_type)
  "vbmc-emulator-#{bmc_type}-#{vbmc_domain_name(machine)}"
end

def vbmc_up(machine, bmc_type, bmc_ip, bmc_port)
  case bmc_type
  when 'redfish'
    vbmc_up_redfish(machine, bmc_type, bmc_ip, bmc_port)
  when 'ipmi'
    vbmc_up_ipmi(machine, bmc_type, bmc_ip, bmc_port)
  end
end

def vbmc_up_redfish(machine, bmc_type, bmc_ip, bmc_port)
  vbmc_destroy(machine, bmc_type)
  container_name = vbmc_container_name(machine, bmc_type)
  machine.ui.info("Creating the #{container_name} docker container...")
  stdout, stderr, status = Open3.capture3(
    'docker',
    'run',
    '--rm',
    '--name',
    container_name,
    '--detach',
    '-v',
    '/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock',
    '-v',
    '/var/run/libvirt/libvirt-sock-ro:/var/run/libvirt/libvirt-sock-ro',
    '-e',
    "SUSHY_EMULATOR_ALLOWED_INSTANCES=#{machine.id}",
    '-p',
    "#{bmc_ip}:#{bmc_port}:8000/tcp",
    'ruilopes/sushy-vbmc-emulator')
  if status.exitstatus != 0
    if stderr.include? 'No such container'
      return
    end
    raise "failed to run the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
end

def vbmc_up_ipmi(machine, bmc_type, bmc_ip, bmc_port)
  vbmc_destroy(machine, bmc_type)
  container_name = vbmc_container_name(machine, bmc_type)
  machine.ui.info("Creating the #{container_name} docker container...")
  stdout, stderr, status = Open3.capture3(
    'docker',
    'run',
    '--rm',
    '--name',
    container_name,
    '--detach',
    '-v',
    '/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock',
    '-v',
    '/var/run/libvirt/libvirt-sock-ro:/var/run/libvirt/libvirt-sock-ro',
    '-e',
    "VBMC_EMULATOR_DOMAIN_NAME=#{vbmc_domain_name(machine)}",
    '-e',
    "VBMC_EMULATOR_USERNAME=admin",
    '-e',
    "VBMC_EMULATOR_PASSWORD=password",
    '-p',
    "#{bmc_ip}:#{bmc_port}:6230/udp",
    'ruilopes/vbmc-emulator')
  if status.exitstatus != 0
    if stderr.include? 'No such container'
      return
    end
    raise "failed to run the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
end

def vbmc_destroy(machine, bmc_type)
  container_name = vbmc_container_name(machine, bmc_type)
  stdout, stderr, status = Open3.capture3('docker', 'inspect', container_name)
  if status.exitstatus != 0
    if stderr.include? 'No such object'
      return
    end
    raise "failed to inspect the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
  machine.ui.info("Destroying the #{container_name} docker container...")
  stdout, stderr, status = Open3.capture3('docker', 'kill', '--signal', 'INT', container_name)
  if status.exitstatus != 0
    if stderr.include? 'No such container'
      return
    end
    raise "failed to kill the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
  stdout, stderr, status = Open3.capture3('docker', 'wait', container_name)
  if status.exitstatus != 0
    if stderr.include? 'No such container'
      return
    end
    raise "failed to wait for the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
  return
end
