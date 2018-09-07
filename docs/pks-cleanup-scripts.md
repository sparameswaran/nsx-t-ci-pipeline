## PKS related scripts

### Freeing up all used up ips from the External IP Pool:

```
#!/bin/bash

NSX_MGR_ADDR=EDIT_ME
NSX_ADMIN=EDIT_ME
NSX_PASSWD=EDIT_ME
POOL_NAME=snat-vip-pool-for-pks # EDIT ME

pool_id=$(curl -k -u "$NSX_ADMIN:$NSX_PASSWD" https://${NSX_MGR_ADDR}/api/v1/pools/ip-pools/  2>/dev/null | jq -r --arg pool_name $POOL_NAME '.results[] | select ( .display_name | contains($pool_name) ) | .id ' )
echo "Given Pool Name: $POOL_NAME and pool id is $pool_id"

ip_range=$(curl -k -u "$NSX_ADMIN:$NSX_PASSWD" https://${NSX_MGR_ADDR}/api/v1/pools/ip-pools/$pool_id   2>/dev/null |jq '.subnets[0].allocation_ranges[0]' | sed -e 's/end/end_ip/g')
echo "Pool IP range is $ip_range"

subnet=$(echo $ip_range | jq -r '.start' | awk -F '.' '{print $1"."$2"."$3}' )
start_ip=$(echo $ip_range | jq -r '.start' | awk -F '.' '{print $4} ' )
end_ip=$(echo $ip_range | jq -r .end_ip | awk -F '.' '{print $4}' )
echo "Pool Subnet is $subnet, start_ip is $start_ip and end_ip is $end_ip"

for offset in $(seq $start_ip $end_ip);
do
   echo Cleaning up IP:  ${subnet}.${offset}
   curl -k -u "$NSX_ADMIN:$NSX_PASSWD" \
           -H 'Content-type: application/json' \
           -X POST -d "{ \"allocation_id\": \"${subnet}.$offset\" }" \
           https://${NSX_MGR_ADDR}/api/v1/pools/ip-pools/$pool_id?action=RELEASE
   echo ""
done

```

### Cleaning up stale or unwanted/left over loadbalancers, virtual servers and server pools

List the lbrs, pools and virtual servers and save them into text files:

```
#!/bin/bash


NSX_MGR_ADDR=EDIT_ME
NSX_ADMIN=EDIT_ME
NSX_PASSWD=EDIT_ME

echo "Checking for Server Pools"
URI=loadbalancer/pools
CURL_CMD="curl -k https://${NSX_MGR_ADDR}/api/v1/${URI} -u ${NSX_ADMIN}:${NSX_PASSWD}"
${CURL_CMD} | jq -r .results[].display_name > pools.txt
echo ---- >> pools.txt
${CURL_CMD} | jq -r .results[].id >> pools.txt

echo "Checking for Virtual servers"
URI=loadbalancer/virtual-servers
CURL_CMD="curl -k https://${NSX_MGR_ADDR}/api/v1/${URI} -u ${NSX_ADMIN}:${NSX_PASSWD}"
${CURL_CMD} | jq -r .results[].display_name > vips.txt
echo ---- >> vips.txt
${CURL_CMD} | jq -r .results[].id >> vips.txt

echo "Checking for Loadbalancer instances"
URI=loadbalancer/services
CURL_CMD="curl -k https://${NSX_MGR_ADDR}/api/v1/${URI}  -u ${NSX_ADMIN}:${NSX_PASSWD}"
${CURL_CMD} | jq -r .results[].display_name > lbrs.txt
echo ---- >> lbrs.txt
${CURL_CMD} | jq -r .results[].id >> lbrs.txt
```

Remove the ids of those resources (name and id are in same order with `----` break between them) that you dont want to clean/remove. Leave only those that need to be deleted.

Check against NSX Mgr before proceeding with deletion.
Then clean up the list of unwanted/stale resources. Then run following:

```
#!/bin/bash

NSX_MGR_ADDR=EDIT_ME
NSX_ADMIN=EDIT_ME
NSX_PASSWD=EDIT_ME

echo "Deleting Loadbalancer instances first"
URI=loadbalancer/services
for id in $(cat lbrs.txt)
do
  curl -k -X DELETE  https://${NSX_MGR_ADDR}/api/v1/${URI}/${id}  -u ${NSX_ADMIN}:${NSX_PASSWD} -H "X-Allow-Overwrite: true"
done

read x
echo "Deleting Virtual Servers next"
URI=loadbalancer/virtual-servers
for id in $(cat vips.txt)
do
  curl -k -X DELETE  https://${NSX_MGR_ADDR}/api/v1/${URI}/${id}  -u ${NSX_ADMIN}:${NSX_PASSWD} -H "X-Allow-Overwrite: true"
done
read x

echo "Deleting Server Pools last!!"
URI=loadbalancer/pools
for id in $(cat pools.txt)
do
  curl -k -X DELETE  https://${NSX_MGR_ADDR}/api/v1/${URI}/${id}  -u ${NSX_ADMIN}:${NSX_PASSWD} -H "X-Allow-Overwrite: true"
done

```
