#!/bin/bash
# TODO(trown): remove hardcoding of net-id

openstack server create \
	--user-data ./CI-DNS.ign \
	--image rhcos \
	--flavor m1.medium \
	--security-group default \
	--security-group ci-dns \
	--config-drive=true \
	--nic net-id=b978d863-7437-465d-86df-d1a5686f797f \
	ci-dns

