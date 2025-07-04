#!/bin/bash
#
# Copyright © 2016-2020 The Thingsboard Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

kubectl -n thingsboard apply -f tb-db-setup-pod.yml &&
kubectl -n thingsboard wait --for=condition=Ready pod/tb-db-setup --timeout=120s &&
kubectl -n thingsboard exec tb-db-setup -- sh -c 'export UPGRADE_TB=true; start-tb-node.sh; touch /tmp/install-finished;'

kubectl -n thingsboard delete pod tb-db-setup
