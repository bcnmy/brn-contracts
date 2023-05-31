# Setup Anvil
anvil --block-time 1

# Deploy the contracts (separate terminal)
FOUNDRY_PROFILE=test ./script/TA.Deploy.Testnet.sh

# Run the simulation
npx ts-node hardhat/testnet/index.ts