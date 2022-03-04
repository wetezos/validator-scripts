#!/bin/bash -e

##############################################################################################################################################################
# User settings.
##############################################################################################################################################################

KEY=""                                  # This is the key you wish to use for signing transactions, listed in first column of "${CLI_NAME} keys list".
DENOM="aevmos"                           
MINIMUM_DELEGATION_AMOUNT="500000000"    
RESERVATION_AMOUNT="100000000"        
VALIDATOR=""                            # Validator Operator Address
CLI_NAME='evmosd'
##############################################################################################################################################################


##############################################################################################################################################################
# Sensible defaults.
##############################################################################################################################################################

CHAIN_ID="evmos_9001-1"                                     # Current chain id. Empty means auto-detect.
NODE="http://127.0.0.1:26657"  # Either run a local full node or choose one you trust.
GAS_PRICES=""                         # Gas prices to pay for transaction.
GAS_ADJUSTMENT="1.30"                           # Adjustment for estimated gas
GAS_FLAGS="--gas auto --gas-prices ${GAS_PRICES} --gas-adjustment ${GAS_ADJUSTMENT}"

##############################################################################################################################################################

echo "Enter your key PASSPHRASE:"
read -s PASSPHRASE

while true
do
    # Auto-detect chain-id if not specified.
    if [ -z "${CHAIN_ID}" ]
    then
    NODE_STATUS=$(curl -s --max-time 5 ${NODE}/status)
    CHAIN_ID=$(echo ${NODE_STATUS} | jq -r ".result.node_info.network")
    fi
    # Use first command line argument in case KEY is not defined.
    if [ -z "${KEY}" ] && [ ! -z "${1}" ]
    then
    KEY=${1}
    fi
    # Get information about key
    KEY_STATUS=$(echo ${PASSPHRASE} | ${CLI_NAME} keys show ${KEY} --output json)
    KEY_TYPE=$(echo ${KEY_STATUS} | jq -r ".type")
    if [ "${KEY_TYPE}" == "ledger" ]
    then
    SIGNING_FLAGS="--ledger"
    fi
    # Get current account balance.
    ACCOUNT_ADDRESS=$(echo ${KEY_STATUS} | jq -r ".address")
    ACCOUNT_STATUS=$(${CLI_NAME} query account ${ACCOUNT_ADDRESS} --chain-id ${CHAIN_ID} --node ${NODE} --output json)
    ACCOUNT_SEQUENCE=$(echo ${ACCOUNT_STATUS} | jq -r ".base_account" |jq -r ".sequence")
    ACCOUNT_INFO=$(${CLI_NAME} query bank balances ${ACCOUNT_ADDRESS} --chain-id ${CHAIN_ID} --node ${NODE} --output json)
    ACCOUNT_BALANCE=$(echo ${ACCOUNT_INFO} | jq -r ".balances[] | select(.denom == \"${DENOM}\") | .amount" || true)
    if [ -z "${ACCOUNT_BALANCE}" ]
    then
    # Empty response means zero balance.
    ACCOUNT_BALANCE=0
    fi
    # Get available rewards.
    REWARDS_STATUS=$(${CLI_NAME} query distribution rewards ${ACCOUNT_ADDRESS} --chain-id ${CHAIN_ID} --node ${NODE} --output json)
    if [ "${REWARDS_STATUS}" == "null" ]
    then
    # Empty response means zero balance.
    REWARDS_BALANCE="0"
    else
    REWARDS_BALANCE=$(echo ${REWARDS_STATUS} | jq -r ".rewards[] |.reward[] | select(.denom == \"${DENOM}\") | .amount" || true)
    if [ -z "${REWARDS_BALANCE}" ] || [ "${REWARDS_BALANCE}" == "null" ]
    then
    # Empty response means zero balance.
    REWARDS_BALANCE="0"
    else
    # Remove decimals.
    REWARDS_BALANCE=${REWARDS_BALANCE%.*}
    fi
    fi
    # Get available commission.
    VALIDATOR_ADDRESS=$(echo ${PASSPHRASE} | ${CLI_NAME} keys show ${KEY} --bech val --address)
    COMMISSION_STATUS=$(${CLI_NAME} query distribution commission ${VALIDATOR_ADDRESS} --chain-id ${CHAIN_ID} --node ${NODE} --output json)
    if [ "${COMMISSION_STATUS}" == "null" ]
    then
    # Empty response means zero balance.
    COMMISSION_BALANCE="0"
    else
    COMMISSION_BALANCE=$(echo ${COMMISSION_STATUS} | jq -r ".commission[] | select(.denom == \"${DENOM}\") | .amount" || true)
    if [ -z "${COMMISSION_BALANCE}" ]
    then
    # Empty response means zero balance.
    COMMISSION_BALANCE="0"
    else
    # Remove decimals.
    COMMISSION_BALANCE=${COMMISSION_BALANCE%.*}
    fi
    fi

    # Calculate net balance and amount to delegate.
    NET_BALANCE=$((${ACCOUNT_BALANCE} + ${REWARDS_BALANCE} + ${COMMISSION_BALANCE}))
    if [ "${NET_BALANCE}" -gt $((${MINIMUM_DELEGATION_AMOUNT} + ${RESERVATION_AMOUNT})) ]
    then
    DELEGATION_AMOUNT=$((${NET_BALANCE} - ${RESERVATION_AMOUNT}))
    else
    DELEGATION_AMOUNT="0"
    fi

    # Display what we know so far.
    echo "======================================================"
    echo "Account: ${KEY} (${KEY_TYPE})"
    echo "Address: ${ACCOUNT_ADDRESS}"
    echo "======================================================"
    echo "Account balance:      ${ACCOUNT_BALANCE}${DENOM}"
    echo "Available rewards:    ${REWARDS_BALANCE}${DENOM}"
    echo "Available commission: ${COMMISSION_BALANCE}${DENOM}"
    echo "Net balance:          ${NET_BALANCE}${DENOM}"
    echo "Reservation:          ${RESERVATION_AMOUNT}${DENOM}"
    echo

    if [ "${DELEGATION_AMOUNT}" -eq 0 ]
    then
    echo "Nothing to delegate."
    sleep 120
    continue
    fi

    # Display delegation information.
    VALIDATOR_STATUS=$(${CLI_NAME} query staking validator ${VALIDATOR} --chain-id ${CHAIN_ID} --node ${NODE} --output json)
    VALIDATOR_MONIKER=$(echo ${VALIDATOR_STATUS} | jq -r ".description.moniker")
    VALIDATOR_DETAILS=$(echo ${VALIDATOR_STATUS} | jq -r ".description.details")
    echo "You are about to delegate ${DELEGATION_AMOUNT}${DENOM} to ${VALIDATOR}:"
    echo "  Moniker: ${VALIDATOR_MONIKER}"
    echo "  Details: ${VALIDATOR_DETAILS}"
    echo

    # Ask for passphrase to sign transactions.
    if [ -z "${SIGNING_FLAGS}" ] && [ -z "${PASSPHRASE}" ]
    then
    read -s -p "Enter passphrase required to sign for \"${KEY}\": " PASSPHRASE
    echo ""
    fi

    # Run transactions
    if [ "${REWARDS_BALANCE}" -gt 0 ]
    then
    printf "Withdrawing rewards... "
    echo "${CLI_NAME} tx distribution withdraw-all-rewards --yes --from ${KEY} --sequence ${ACCOUNT_SEQUENCE} --chain-id ${CHAIN_ID} --node ${NODE} ${SIGNING_FLAGS} --broadcast-mode async"
    echo ${PASSPHRASE} | ${CLI_NAME} tx distribution withdraw-all-rewards --yes --from ${KEY} --sequence ${ACCOUNT_SEQUENCE} --chain-id ${CHAIN_ID} --node ${NODE} ${SIGNING_FLAGS} --broadcast-mode async
    ACCOUNT_SEQUENCE=$((ACCOUNT_SEQUENCE + 1))
    fi
    if [ "${COMMISSION_BALANCE}" -gt 0 ]
    then
    printf "Withdrawing commission... "
    echo ${PASSPHRASE} | ${CLI_NAME} tx distribution withdraw-rewards ${VALIDATOR_ADDRESS} --commission --yes --from ${KEY} --sequence ${ACCOUNT_SEQUENCE} --chain-id ${CHAIN_ID} --node ${NODE} ${SIGNING_FLAGS}  --broadcast-mode async
    ACCOUNT_SEQUENCE=$((ACCOUNT_SEQUENCE + 1))
    fi

    printf "Delegating... "
    echo ${PASSPHRASE} | ${CLI_NAME} tx staking delegate ${VALIDATOR} ${DELEGATION_AMOUNT}${DENOM} --yes --from ${KEY} --sequence ${ACCOUNT_SEQUENCE} --chain-id ${CHAIN_ID} --node ${NODE} ${SIGNING_FLAGS} --broadcast-mode async

    echo
    echo "Have a Cosmic day!"


    sleep 3600 
done
