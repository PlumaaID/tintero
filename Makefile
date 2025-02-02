-include .env

.PHONY: all test clean deploy fund help install snapshot coverage format anvil scopefile

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: install clean build

# Clean the repo
clean:; forge clean

# Remove modules
install:; forge install

# Update Dependencies
update:; forge update

build:; forge build

test: clean; forge test

gas-report: clean; forge test --gas-report

snapshot: clean; forge snapshot

coverage: clean; forge coverage --no-match-coverage "script|test"

format:; forge fmt

anvil:; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

slither:; slither . --config-file slither.config.json --checklist 

aderyn:; aderyn .

scopefile:; @tree ./src/ | sed 's/└/#/g' | awk -F '── ' '!/\.sol$$/ { path[int((length($$0) - length($$2))/2)] = $$2; next } { p = "src"; for(i=2; i<=int((length($$0) - length($$2))/2); i++) if (path[i] != "") p = p "/" path[i]; print p "/" $$2; }' > scope.txt

scope:; tree ./src/ | sed 's/└/#/g; s/──/--/g; s/├/#/g; s/│ /|/g; s/│/|/g'

deploy_arbitrum:; ETH_FROM=0x00560ED8242bF346c162c668487BaCD86cc0B8aa forge script script/Deploy.s.sol --rpc-url arbitrum --account plumaa_deployer --broadcast --verify

deploy_arbitrum_sepolia:; ETH_FROM=0x00560ED8242bF346c162c668487BaCD86cc0B8aa forge script script/Deploy.s.sol --rpc-url arbitrum_sepolia --account plumaa_deployer --broadcast --verify
