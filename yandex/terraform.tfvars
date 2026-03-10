pg_dbs = [
  "repricer",
  "space",
  "uzum-scrapper",
  "ke-scrapper",
  "crm",
  "strapi",
  "ke-analytics",
  "uzum-analytics",
  "temporal",
  "temporal_visibility",
  "herald",
  "steambuddy",
  "chainbrain",
  "chainbrain-agent",
  "n8n",
  "endmake"
]
clickhouse_dbs = [
  "uzum",
  "kazanex"
]
db_password                 = "Str0ngPasswd"
db_dev_password             = "Str0ngPasswd"
vm_user_nat                 = "vitaxa"
nat_ssh_key_path            = "./keys/yc-nat.pub"
endmake_public_ingress_ipv4 = "51.250.10.12"

endroom_enable_cdn_resources   = true
endroom_enable_www_cutover     = true
endroom_enable_apex_redirect   = true
endroom_enable_origin_lockdown = false
endroom_cdn_provider_cname     = "43fb6b1550305dfd.topology.gslb.yccdn.ru"
