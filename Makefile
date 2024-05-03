include env.sh
# 変数定義 ------------------------

# SERVER_ID: env.sh内で定義

# 問題によって変わる変数
USER:=isucon
BIN_NAME:=isupipe
BUILD_DIR:=/home/isucon/webapp/go
SERVICE_NAME:=$(BIN_NAME)-go.service

UTILS_PATH=/home/isucon/webapp/utils
DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx
SYSTEMD_PATH:=/etc/systemd/system

NGINX_LOG:=/var/log/nginx/access.log
DB_SLOW_LOG:=/var/log/mysql/slow-query.log
SQLITE_SLOW_LOG=/home/isucon/logs/sqlite/sqlite-slow-query.log

SQLITE_SLOW_LOG=/home/isucon/logs/sqlite/sqlite-slow-query.log

NGINX_LOG_FORMAT:=/etc/nginx/conf.d/log_format.conf
ALP_CONF:=/home/isucon/alp/config.yml
SLOW_QUERY_CONF:=/etc/mysql/mysql.conf.d/slow_query.cnf

PPROF_DIR:=/home/isucon/pprof

DATE:=$(shell date "+%H%M%S")

# メインで使うコマンド ------------------------

# サーバーの環境構築　ツールのインストール、gitまわりのセットアップ
.PHONY: setup
setup: install-tools git-setup make-server-id-dir 

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get-conf
get-conf: check-server-id get-db-conf get-nginx-conf get-service-file get-envsh

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-nginx-conf deploy-service-file deploy-envsh

# ベンチマークを走らせる直前に実行する
.PHONY: bench
bench: check-server-id mv-logs build restart watch-service-log

# slow queryを確認する
.PHONY: slow-query
slow-query:
	sudo pt-query-digest $(DB_SLOW_LOG) > slow-query.txt
	curl -X POST https://discord.com/api/webhooks/1164529073696018452/0NHZIkbcR37P50A8ZNScAPHkG_07FUWGdkdVGHtglP5mXbBDzRTy-l64_VVeO-QfPDfK  -F file=@slow-query.txt	


# alpでアクセスログを確認する
.PHONY: alp
alp:
	sudo alp ltsv --file=$(NGINX_LOG) --config=$(ALP_CONF) -q --qs-ignore-values> alp/alp.txt
	curl -X POST https://discord.com/api/webhooks/1164529073696018452/0NHZIkbcR37P50A8ZNScAPHkG_07FUWGdkdVGHtglP5mXbBDzRTy-l64_VVeO-QfPDfK  -F file=@alp/alp.txt

# dsqでクエリログを確認する（入力データは/home/isucon/logs/querylog.txt）
.PHONY: dsq
dsq:
	bash $(UTILS_PATH)/dsq/check_querylog.sh $(SQLITE_SLOW_LOG) > dsq.txt
	curl -X POST https://discord.com/api/webhooks/1164529073696018452/0NHZIkbcR37P50A8ZNScAPHkG_07FUWGdkdVGHtglP5mXbBDzRTy-l64_VVeO-QfPDfK  -F file=@dsq.txt	

# pprofで記録する
.PHONY: pprof-record
pprof-record:
	go tool pprof http://localhost:6060/debug/pprof/profile

# pprofで確認する
.PHONY: pprof-check
pprof-check:
	$(eval latest := $(shell ls -rt $(PPROF_DIR)/ | tail -n 1))
	go tool pprof -http=0.0.0.0:8090 $(PPROF_DIR)/$(latest)

# fgprofで記録する
.PHONY: fgprof-record
fgprof-record:
	go tool pprof --http=0.0.0.0:8090 http://localhost:6060/debug/fgprof?seconds=60

# DBに接続する
.PHONY: access-db
access-db:
	mysql -h $(MYSQL_HOST) -P $(MYSQL_PORT) -u $(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DBNAME)

# 主要コマンドの構成要素 ------------------------

.PHONY: install-tools
install-tools:
	sudo apt update
	sudo apt upgrade
	sudo apt install -y percona-toolkit dstat git unzip snapd graphviz tree

	# alpのインストール
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.9/alp_linux_amd64.zip
	rm -rf alp
	unzip alp_linux_amd64.zip
	sudo install alp /usr/local/bin/alp
	rm -rf alp_linux_amd64.zip* alp
	mkdir -p /home/isucon/alp
	touch $(ALP_CONF)
	sudo touch $(NGINX_LOG_FORMAT)
	sudo chmod 777 $(NGINX_LOG_FORMAT)

	#pt-query-digestのインストール
	sudo apt install percona-toolkit

	#discordにsetup終了通知を流す
	curl -X POST https://discord.com/api/webhooks/1164529073696018452/0NHZIkbcR37P50A8ZNScAPHkG_07FUWGdkdVGHtglP5mXbBDzRTy-l64_VVeO-QfPDfK  -H 'Content-Type: application/json' --data '{"content": "setup完了"}'

.PHONY: install-dsq
install-dsq:
	# goのインストール
	sudo apt install -y golang-go
	#bsqのインストール
	go install github.com/multiprocessio/dsq@latest
	sudo mv ~/go/bin/dsq /usr/local/bin/dsq
	mkdir -p /home/isucon/logs/sqlite
	sudo chown $(USER) -R /home/isucon/logs/sqlite
	#jqのインストール
	sudo apt install -y jq

.PHONY: git-setup
git-setup:
	# git用の設定は適宜変更して良い
	git config --global user.email "isucon@example.com"
	git config --global user.name "isucon"

	# deploykeyの作成
	ssh-keygen -t ed25519

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

.PHONY: set-as-s1
set-as-s1:
	echo "SERVER_ID=s1" >> env.sh

.PHONY: set-as-s2
set-as-s2:
	echo "SERVER_ID=s2" >> env.sh

.PHONY: set-as-s3
set-as-s3:
	echo "SERVER_ID=s3" >> env.sh

#server-idに紐づいたディレクトリを作成する（本番はいらないかも）
.PHONY: make-server-id-dir
make-server-id-dir:
	sudo mkdir -p ~/$(SERVER_ID)/etc/mysql
	touch ~/$(SERVER_ID)/etc/mysql/dummy.txt
	sudo mkdir -p ~/$(SERVER_ID)/etc/nginx
	touch ~/$(SERVER_ID)/etc/nginx/dummy.txt
	sudo mkdir -p ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)
	touch ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)dummy.txt
	sudo mkdir -p ~/$(SERVER_ID)/home/isucon

.PHONY: get-db-conf
get-db-conf:
	sudo mkdir -p ~/$(SERVER_ID)/etc/mysql
	sudo cp -Rf $(DB_PATH)/* ~/$(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/mysql

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo mkdir -p ~/$(SERVER_ID)/etc/nginx
	sudo cp -Rf $(NGINX_PATH)/* ~/$(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/nginx

.PHONY: get-service-file
get-service-file:
	sudo mkdir -p ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)
	- sudo cp $(SYSTEMD_PATH)/$(SERVICE_NAME) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)
	- sudo chown $(USER) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)

.PHONY: get-envsh
get-envsh:
	sudo mkdir -p ~/$(SERVER_ID)/home/isucon
	sudo touch ~/$(SERVER_ID)/home/isucon/env.sh
	sudo chmod 777 ~/$(SERVER_ID)/home/isucon/env.sh
	cp ~/env.sh ~/$(SERVER_ID)/home/isucon/env.sh

.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -Rf ~/$(SERVER_ID)/etc/mysql/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -Rf ~/$(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

.PHONY: deploy-service-file
deploy-service-file:
	- sudo cp ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME) $(SYSTEMD_PATH)/$(SERVICE_NAME)

.PHONY: deploy-envsh
deploy-envsh:
	-  hcp ~/$(SERVER_ID)/home/isucon/env.sh ~/env.sh

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)
	sudo systemctl restart mysql
	sudo systemctl restart nginx

.PHONY: mv-logs
mv-logs:
	@echo "\e[32mlogファイルを初期化します\e[m"
	mkdir -p ~/logs/$(DATE)
	-sudo mv -f $(DB_SLOW_LOG) ~/logs/$(DATE)/slow-query.txt
	-sudo mv -f $(NGINX_LOG) ~/logs/$(DATE)/access.txt
	-sudo cp -f $(SQLITE_SLOW_LOG) ~/logs/$(DATE)/sqlite_slow_query.txt
	-echo -n > $(SQLITE_SLOW_LOG)	

.PHONY: watch-service-log
watch-se:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f


