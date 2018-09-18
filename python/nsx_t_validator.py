#!/usr/bin/env python

# nsx-t-validator
#
# Copyright (c) 2015-Present Pivotal Software, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

__author__ = 'Sabha Parameswaran'

import httplib
import os
import json
import yaml
from pprint import pprint
import client


API_VERSION                  = '/api/v1'

EDGE_CLUSTERS_ENDPOINT       = '%s%s' % (API_VERSION, '/edge-clusters')
TRANSPORT_ZONES_ENDPOINT     = '%s%s' % (API_VERSION, '/transport-zones')
ROUTERS_ENDPOINT             = '%s%s' % (API_VERSION, '/logical-routers')
ROUTER_PORTS_ENDPOINT        = '%s%s' % (API_VERSION, '/logical-router-ports')
SWITCHES_ENDPOINT            = '%s%s' % (API_VERSION, '/logical-switches')
SWITCH_PORTS_ENDPOINT        = '%s%s' % (API_VERSION, '/logical-ports')
SWITCHING_PROFILE_ENDPOINT   = '%s%s' % (API_VERSION, '/switching-profiles')
CONTAINER_IP_BLOCKS_ENDPOINT = '%s%s' % (API_VERSION, '/pools/ip-blocks')
EXTERNAL_IP_POOL_ENDPOINT    = '%s%s' % (API_VERSION, '/pools/ip-pools')
NSGROUP_ENDPOINT             = '%s%s' % (API_VERSION, '/ns-groups')
TRUST_MGMT_CSRS_ENDPOINT     = '%s%s' % (API_VERSION, '/trust-management/csrs')
TRUST_MGMT_CRLS_ENDPOINT     = '%s%s' % (API_VERSION, '/trust-management/crls')
TRUST_MGMT_SELF_SIGN_CERT    = '%s%s' % (API_VERSION, '/trust-management/csrs/')
TRUST_MGMT_UPDATE_CERT       = '%s%s' % (API_VERSION, '/node/services/http?action=apply_certificate')
LBR_SERVICES_ENDPOINT        = '%s%s' % (API_VERSION, '/loadbalancer/services')
LBR_VIRTUAL_SERVER_ENDPOINT  = '%s%s' % (API_VERSION, '/loadbalancer/virtual-servers')
LBR_POOLS_ENDPOINT           = '%s%s' % (API_VERSION, '/loadbalancer/pools')
LBR_MONITORS_ENDPOINT        = '%s%s' % (API_VERSION, '/loadbalancer/monitors')

LBR_APPLICATION_PROFILE_ENDPOINT = '%s%s' % (API_VERSION, '/loadbalancer/application-profiles')
LBR_PERSISTENCE_PROFILE_ENDPOINT = '%s%s' % (API_VERSION, '/loadbalancer/persistence-profiles')

global_id_map = { }

DEBUG = True
failed = False

def init():

    global nsx_mgr_ip, validate_for_pas

    nsx_mgr_ip          = os.getenv('NSX_API_MANAGER')
    nsx_mgr_user        = os.getenv('NSX_API_USER', 'admin')
    nsx_mgr_pwd         = os.getenv('NSX_API_PASSWORD')
    validate_for_pas    = ( os.getenv('VALIDATE_FOR_PAS', 'true') == 'true' )

    nsx_mgr_context     = {
                          'admin_user' : nsx_mgr_user,
                          'url': 'https://' + nsx_mgr_ip,
                          'admin_passwd' : nsx_mgr_pwd
                        }
    #print 'NSX Mgr context: {}'.format(nsx_mgr_context)
    client.set_context(nsx_mgr_context)

def check_connect():
    try:
        conn = httplib.HTTPSConnection(nsx_mgr_ip)
        conn.request("GET", "/")
        response = conn.getresponse()
        #print response.status, response.reason
        #data = response.read()
        #print data
    except IOError, e:
        if 'unknown protocol' in str(e):
            # Ignore unknown protocol as we just tried to do raw connection over https
            # Sample error: [SSL: UNKNOWN_PROTOCOL] unknown protocol (_ssl.c:590)
            print 'Successfully connected to NSX Mgr at: https://{}\n'.format(nsx_mgr_ip)
            return

        print 'Problem in communicating with NSX Server at {}, error: {}'.format(nsx_mgr_ip, e)
        exit(-1)

def check_basic_auth():
    api_endpoint = ROUTERS_ENDPOINT
    resp=client.get(api_endpoint, check=False)

    #for router in resp.json()['results']:
    if resp.status_code > 400:
        print resp.status_code
        print 'Problem in communicating with NSX Server at {}, error: {}'.format(nsx_mgr_ip, resp.json()['error_message'])
        exit(1)

def check_for_match(resource_type, given_list, existing_list):
    global failed

    print 'Checking for {} entries\n\tGiven: {}\n\tDiscovered: {}'.format(resource_type, given_list, existing_list)
    for given_name in given_list:
        if not given_name in existing_list:
            failed = True
            print 'Error!! Unable to find the specified {}: {}'.format(resource_type, given_name)
            print 'Ignore if new Container IP Pool or External IP Block needs to be created!!\n'
    if not failed:
        print 'Validation successful for {}!!\n'.format(resource_type)

    return failed

def check_for_overlay_zone(given_names):
    api_endpoint = TRANSPORT_ZONES_ENDPOINT
    resp=client.get(api_endpoint, check=False)

    existing_names = []
    for tz in resp.json()['results']:
        existing_names.append(tz['display_name'])

    return check_for_match('Transport Zone', given_names, existing_names)

def check_cluster_name_against_router(t0_router_name, given_foundation_name):
    global failed

    api_endpoint = ROUTERS_ENDPOINT
    resp=client.get(api_endpoint, check=False)

    for router in resp.json()['results']:
        if t0_router_name == router['display_name']:
            tags = router.get('tags')
            if not tags:
                failed = True
                print 'Error!! T0 Router: {} not tagged correctly!!'
                return

            for tag_entry in tags:
                if tag_entry.get('scope') == 'ncp/cluster':
                    if given_foundation_name != tag_entry.get('tag'):
                        failed = True
                        print 'Error!! Specified foundation name: {} not tagged for T0 Router: {} not correctly tagged' \
                                    ' with \'ncp/cluster\' scope!!\n'.format(given_foundation_name, t0_router_name)
                        return
                    else:
                        print 'Specified foundation name: {} tagged correctly against T0 Router: {} ' \
                                    ' with \'ncp/cluster\' scope!!\n'.format(given_foundation_name, t0_router_name)
                        return

            failed = True
            print 'Error!! T0 Router: {} not correctly tagged with \'ncp/cluster\' scope!!\n'.format(t0_router_name)
            return

def check_for_routers(given_names):
    api_endpoint = ROUTERS_ENDPOINT
    resp=client.get(api_endpoint, check=False)

    existing_names = []
    for router in resp.json()['results']:
        existing_names.append(router['display_name'])

    return check_for_match('T0 Router', given_names, existing_names)

def check_for_ip_pools(given_names):
    api_endpoint = EXTERNAL_IP_POOL_ENDPOINT
    resp=client.get(api_endpoint, check=False)

    existing_names = []
    for ip_pool in resp.json()['results']:
        existing_names.append(ip_pool['display_name'])

    return check_for_match('IP Pool', given_names, existing_names)

def check_for_ip_blocks(given_names):
    api_endpoint = CONTAINER_IP_BLOCKS_ENDPOINT
    resp=client.get(api_endpoint, check=False)

    existing_names = []
    for ip_block in resp.json()['results']:
        existing_names.append(ip_block['display_name'])

    return check_for_match('IP Block', given_names, existing_names)

def check_for_security_groups(given_names):
    api_endpoint = NSGROUP_ENDPOINT
    resp=client.get(api_endpoint, check=False)

    existing_names = []
    for nsg in resp.json()['results']:
        existing_names.append(nsg['display_name'])

    return check_for_match('NS Group', given_names, existing_names)

def get_names_from_yaml_payload(yaml_payload, nested_element):
    names = []
    resource_type = nested_element.replace('_', ' ').strip('s')

    entries = yaml.load(yaml_payload)
    for entry in entries[nested_element]:
        entry_name   = entry['name']
        entry_cidr   = entry.get('cidr')
        if not entry_cidr:
            names.append(entry_name)
        else:
            print 'Not checking for {} \'{}\', cidr populated, probably needs to be created!!\n'.format(resource_type, entry_name)

    return names


def run_pas_validate():
    global failed
    print 'Running PAS validation!!'
    
    overlay_zone = os.getenv('NSX_T_OVERLAY_TRANSPORT_ZONE')
    if overlay_zone == '' or not overlay_zone:
        print 'Transport Zone set to be empty'
        failed = True
    else:
        check_for_overlay_zone([ overlay_zone ])

    router_name = os.getenv('NSX_T_T0ROUTER_NAME')
    if router_name == '' or not router_name:
        print 'T0 Router set to be empty'
        failed = True
    else:
        check_for_routers([ router_name ])

    foundation_name = os.getenv('NSX_FOUNDATION_NAME')
    check_cluster_name_against_router(router_name, foundation_name)

    container_ip_block_defn = os.getenv('NSX_T_CONTAINER_IP_BLOCK_SPEC', '').strip()
    if container_ip_block_defn == '' or not container_ip_block_defn:
        print 'Container IP Block set to be empty'
        failed = True
    else:
        container_ip_block_names = get_names_from_yaml_payload(container_ip_block_defn, 'container_ip_blocks')
        if container_ip_block_names:
            check_for_ip_blocks(container_ip_block_names)

    external_ip_pool_defn = os.getenv('NSX_T_EXTERNAL_IP_POOL_SPEC', '').strip()
    if external_ip_pool_defn == '' or not external_ip_pool_defn:
        print 'External IP Pool set to be empty'
        failed = True
    else:
        ext_ip_pool_names = get_names_from_yaml_payload(external_ip_pool_defn, 'external_ip_pools')
        if ext_ip_pool_names:
            check_for_ip_pools(ext_ip_pool_names)

    exit(failed)

def run_pks_validate():
    global failed
    print 'Running PKS validation!!'

    router_name = os.getenv('PKS_T0_ROUTER_NAME')
    if router_name == '' or not router_name:
        print 'T0 Router set to be empty'
        failed = True
    else:
        check_for_routers([ router_name ])

    container_ip_block = os.getenv('PKS_CONTAINER_IP_BLOCK_NAME', '').strip()
    node_ip_block = os.getenv('PKS_NODES_IP_BLOCK_NAME', '').strip()

    ip_blocks = []
    if container_ip_block == '' or not container_ip_block:
        failed = True
        print 'Error!! Container IP Block name set to be empty'
    else:
        ip_blocks.append(container_ip_block)

    if node_ip_block == '' or not node_ip_block:
        failed = True
        print 'Error!! Node IP Block name set to be empty'
    else:
        ip_blocks.append(node_ip_block)

    if ip_blocks:
        check_for_ip_blocks(ip_blocks)

    external_ip_pool = os.getenv('PKS_EXTERNAL_IP_POOL_NAME', '').strip()
    if external_ip_pool == '' or not external_ip_pool:
        failed = True
        print 'External IP Pool set to be empty'
    else:
        check_for_ip_pools([external_ip_pool])

    vcenter_cluster_names = os.getenv('PKS_VCENTER_CLUSTER_LIST')
    if vcenter_cluster_names == '' or not vcenter_cluster_names:
        print 'vCenter Cluster set to be empty'
        failed = True

    exit(failed)

def main():

    init()
    check_connect()
    check_basic_auth()

    if validate_for_pas:
        run_pas_validate()
    else:
        run_pks_validate()



if __name__ == '__main__':
    main()
