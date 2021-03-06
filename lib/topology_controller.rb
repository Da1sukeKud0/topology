require "command_line"
require "topology_manager"
require "rtc_manager"

class TopologyController < Trema::Controller
  timer_event :flood_lldp_frames, interval: 1.sec

  attr_reader :topology

  def start(args)
    @command_line = CommandLine.new(logger)
    @command_line.parse(args)
    @topology = TopologyManager.new
    @topology.add_observer @command_line.view
    logger.info "Topology started (#{@command_line.view})."
    @rtcManager = RTCManager.new
    @test_counter = 1
    @test_mac_table = Hash.new
  end

  def add_observer(observer)
    @topology.add_observer observer
  end

  def switch_ready(dpid)
    send_message dpid, Features::Request.new
  end

  def features_reply(dpid, features_reply)
    @topology.add_switch dpid, features_reply.physical_ports.select(&:up?)
  end

  def switch_disconnected(dpid)
    @topology.delete_switch dpid
  end

  def port_modify(_dpid, port_status)
    updated_port = port_status.desc
    return if updated_port.local?
    if updated_port.down?
      @topology.delete_port updated_port
    elsif updated_port.up?
      @topology.add_port updated_port
    else
      fail "Unknown port status."
    end
  end

  def packet_in(dpid, packet_in)
    if packet_in.lldp?
      @topology.maybe_add_link Link.new(dpid, packet_in)
    else
      puts "packet_in (not LLDP)"
      @topology.maybe_add_host(packet_in.source_mac, packet_in.source_ip_address, dpid, packet_in.in_port)
      ##ipとportの紐付け
      # send_flow_mod_add(
      #   packet_in.datapath_id,
      #   match: Match.new(destination_ip_address: packet_in.source_ip_address),
      #   actions: SendOutPort.new(packet_in.in_port)
      # )
      @test_mac_table[@test_counter] = packet_in.source_mac
      if (@test_counter == 7)
        hsrc = @topology.hosts[@test_mac_table[1]]
        hdst = @topology.hosts[@test_mac_table[6]]
        startwatch("add_rtc?呼び出し")
        @rtcManager.add_rtc?(hsrc, hdst, 2, @topology.topo)
        stopwatch("スケジューリング可")
      end
      if (@test_counter == 8)
        hsrc = @topology.hosts[@test_mac_table[1]]
        hdst = @topology.hosts[@test_mac_table[6]]
        startwatch("add_rtc?呼び出し")
        @rtcManager.add_rtc?(hsrc, hdst, 2, @topology.topo)
        stopwatch("スケジューリング可")
      end
      if (@test_counter == 9)
        hsrc = @topology.hosts[@test_mac_table[4]]
        hdst = @topology.hosts[@test_mac_table[5]]
        startwatch("add_rtc?呼び出し")
        @rtcManager.add_rtc?(hsrc, hdst, 5, @topology.topo)
        stopwatch("スケジューリング可")
        # puts "flow_mod"
        # send_flow_mod_add(
        #   1,
        #   match: Match.new(in_port: 3),
        #   actions: SendOutPort.new(2),
        # )
        # send_flow_mod_add(
        #   4,
        #   match: Match.new(in_port: 1),
        #   actions: SendOutPort.new(3),
        # )
        # send_flow_mod_add(
        #   6,
        #   match: Match.new(in_port: 2),
        #   actions: SendOutPort.new(4),
        # )
      end
      # if (@test_counter == 9)
      #   hsrc = @topology.hosts[@test_mac_table[4]]
      #   hdst = @topology.hosts[@test_mac_table[5]]
      #   @rtcManager.add_rtc?(hsrc, hdst, 5, @topology.topo)
      # end
      # if (@test_counter == 8)
      #   hsrc = @topology.hosts[@test_mac_table[1]]
      #   hdst = @topology.hosts[@test_mac_table[6]]
      #   @rtcManager.add_rtc?(hsrc, hdst, 3, @topology.topo)
      # end
      # if (@test_counter == 9)
      #   hsrc = @topology.hosts[@test_mac_table[1]]
      #   hdst = @topology.hosts[@test_mac_table[6]]
      #   @rtcManager.add_rtc?(hsrc, hdst, 3, @topology.topo)
      # end
      # if (@test_counter == 10)
      #   hsrc = @topology.hosts[@test_mac_table[1]]
      #   hdst = @topology.hosts[@test_mac_table[6]]
      #   @rtcManager.add_rtc?(hsrc, hdst, 3, @topology.topo)
      # end
      @test_counter += 1
    end
  end

  def flood_lldp_frames
    @topology.ports.each do |dpid, ports|
      send_lldp dpid, ports
    end
  end

  private

  def send_lldp(dpid, ports)
    ports.each do |each|
      port_number = each.number
      send_packet_out(
        dpid,
        actions: SendOutPort.new(port_number),
        raw_data: lldp_binary_string(dpid, port_number),
      )
    end
  end

  def lldp_binary_string(dpid, port_number)
    destination_mac = @command_line.destination_mac
    if destination_mac
      Pio::Lldp.new(dpid: dpid,
                    port_number: port_number,
                    destination_mac: destination_mac).to_binary
    else
      Pio::Lldp.new(dpid: dpid, port_number: port_number).to_binary
    end
  end

  ##
  ## タイマー
  def startwatch(tag)
    @timer = Time.now
    @old_tag = tag
  end

  ##
  ## 前回の呼び出しからの経過時間を測定
  def stopwatch(tag)
    if @timer
      puts ""
      puts "during time of #{@old_tag} to #{tag}: #{Time.now - @timer}"
      puts ""
    end
  end
end
