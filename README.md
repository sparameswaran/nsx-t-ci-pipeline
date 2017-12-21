# nsx-t-ci-pipeline

Install Concourse and Pivotal PAS/PCF 2.0 with VMware NSX-T (Add-on) Tile for PCF.
NOTE: The tool and scripts don't install the full VMware NSX-T or automate creation of NSX-T Routers or Logical switches.

The tools in this repo only help in automating the install of [Concourse](http://concourse.ci/), followed by install of [Pivotal Ops Mr and PCF/PAS](https://network.pivotal.io) on [VMware NSX-T](https://docs.vmware.com/en/VMware-NSX-T/index.html) managed network infrastructure. The Pivotal Cloud Foundry or Application service (PAS) would use NSX-T for the CNI implementation, instead of the default Silk as CNI.

![](docs/nsx-t-ci-pipeline.png)

## Installing Concourse

Edit the scripts and templates under Concourse to setup a BOSH Director and use that to deploy Concourse.
This concourse install would be used later to install Pivotal Ops Mgr 2.0, NSX-T Add-on Tile and Pivotal Application Service Tiles. 

### Bringing up Bosh Director
* Edit the concourse/bosh/vsphere-config.yml and concourse/bosh/vsphere/cloud-config.yml
* Run ```source scripts/setup.sh; cd concourse/bosh; ./bosh-create-env.sh```
* Now the bosh director should have come up (if the configurations are correct)

### Bringing up Concourse
* Edit the concourse/concourse-manifest.yml and concourse/concourse-params.yml
* Run ```source scripts/setup.sh; cd concourse; ./deploy.sh```
* Now the Concourse should have come up (if the configurations are correct)

## Installing Pivotal Ops Mgr and Cloud Foundry Deployment
* Create a params.yml using the piplines/params.sample.yml as template (under pipelines or other folder)
* Edit the values for the various tile versions, vcenter endpoints, network segments, creds etc.
* Edit the install-pcf-pipeline.yml if needed (it installs MySQL, RabbitMQ and Spring Cloud Service in addition to PAS/ERT tile)
* Edit the setup.sh script (changing the url for the concourse web endpoint, name of the pipeline, path to the params file etc.)
* Run `source setup.sh`
* Run `fly-s` to register the pipeline
* Hit unpause on pipeline in the Concourse UI (referred as the web ui endpoint for concourse) or using ```fly -t <target> unpause-pipeline -p <pipeline-name>```
* Check on progress using `fly ... watch` or `fly-h <build-no>`


### Running Cloud Foundry Acceptance tests
* Register the cf acceptance test pipeline using `fly -t <target> set-pipeline -p cf-acceptance-pipeline -c cf-acceptance-tests-pipeline -l params.yml` to register the acceptance test pipeline
* Hit unpause on pipeline in the Concourse UI (referred as the web ui endpoint for concourse) or using ```fly -t <target> unpause-pipeline -p <pipeline-name>```
* Check on progress using `fly ... watch` or `fly-h <build-no>`


