connections {
  ${SS_NAME} {
    local_addrs = %any
    remote_addrs = ${REMOTE_ADDR}
    vips = 0.0.0.0
    fragmentation = yes
    local {
      auth = pubkey
      id = "${LOCAL_ID}"
      certs = ${LOCAL_CERT}
    }
    remote {
      auth = pubkey
      id = "${REMOTE_ID}"
    }
    children {
      tun_${SS_NAME} {
        local_ts = 0.0.0.0/0
        remote_ts = 0.0.0.0/0
        if_id_in = ${IF_ID}
        if_id_out = ${IF_ID}
        start_action = start
        esp_proposals = ${ESP_PROPOSALS}
        mode = tunnel
        life_time = 66m
        rekey_time = 1h
        dpd_action = start
      }
    }
    version = 2
    mobike = yes
    rekey_time = 4h
    over_time = 24m
    proposals = ${IKE_PROPOSALS}
    dpd_delay = 30s
    keyingtries = 0
  }
}

authorities {
  radiusdesk {
    cacert = ${CA_CERT}
  }
}


