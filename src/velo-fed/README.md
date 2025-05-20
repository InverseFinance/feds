**Velodrome Fed**

The goal of the Velodrome fed is to provide liquidity into the DOLA/USDC pool on Velodrome, then stake the LP tokens to earn Velo token rewards.

The Velodrome fed has two main parts: OptiFed.sol and VeloFarmer.sol.

The OptiFed will be deployed on Ethereum mainnet and will handle minting DOLA, swapping DOLA->USDC through the exchange proxy, bridging to Optimism, and burning DOLA.

The VeloFarmer will be deployed on Optimism mainnet and mostly handles depositing/withdrawing DOLA/USDC liquidity on Velodrome along with claiming Velo token rewards. The VeloFarmer can perform swaps if needed, but L2 DOLA liquidity isn't great so L1 is preferred for swaps. It can also bridge both USDC & DOLA back to the L1 OptiFed to be swapped into DOLA & contracted.

**Roles**

The OptiFed and VeloFarmer each have the same 2 privileged roles: gov & chair. Gov has the ability to change contract variables, such as max slippage % as well as roles. The chair can be thought of as an "operator", having the ability to expand/contract DOLA supply, perform swaps, bridge tokens, deposit/withdraw liquidity, etc on behalf of the smart contracts.

This is implemented as basic access control for the OptiFed. For the VeloFarmer, these roles must be checked differently since we want the ability to send cross-chain messages using our L1 multisig for gov actions. To do this, we use the Optimism cross domain messenger (https://community.optimism.io/docs/developers/bridge/messaging/#accessing-msg-sender). This way, we can set gov & chair to normal L1 addresses and our contract will be able to verify that any incoming cross-domain messages originate from a privileged address on L1.

However, gov & chair will likely be set to the address of a deployed VeloFarmerMessenger.sol in order to make operating easier. This Messenger contract is simply an interface to make calling functions cross-chain easier for the person operating these contracts. The flow is: gov/chair address calls a function on L1 VeloFarmerMessenger.sol, VeloFarmerMessenger verifies that sender has correct role to make the call, message is crafted & passed to Optimism bridge, ~15 min later the tx lands on Optimism with VeloFarmerMessenger's address as the xDomainMessageSender which is validated before any logic is executed.
;
