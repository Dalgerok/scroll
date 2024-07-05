// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdToml} from "forge-std/StdToml.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {EmptyContract} from "../../src/misc/EmptyContract.sol";

import {EnforcedTxGateway} from "../../src/L1/gateways/EnforcedTxGateway.sol";
import {L1CustomERC20Gateway} from "../../src/L1/gateways/L1CustomERC20Gateway.sol";
import {L1ERC1155Gateway} from "../../src/L1/gateways/L1ERC1155Gateway.sol";
import {L1ERC721Gateway} from "../../src/L1/gateways/L1ERC721Gateway.sol";
import {L1ETHGateway} from "../../src/L1/gateways/L1ETHGateway.sol";
import {L1GatewayRouter} from "../../src/L1/gateways/L1GatewayRouter.sol";
import {L1MessageQueueWithGasPriceOracle} from "../../src/L1/rollup/L1MessageQueueWithGasPriceOracle.sol";
import {L1ScrollMessenger} from "../../src/L1/L1ScrollMessenger.sol";
import {L1StandardERC20Gateway} from "../../src/L1/gateways/L1StandardERC20Gateway.sol";
import {L1WETHGateway} from "../../src/L1/gateways/L1WETHGateway.sol";
import {L2GasPriceOracle} from "../../src/L1/rollup/L2GasPriceOracle.sol";
import {MultipleVersionRollupVerifier} from "../../src/L1/rollup/MultipleVersionRollupVerifier.sol";
import {ScrollChain} from "../../src/L1/rollup/ScrollChain.sol";
import {ZkEvmVerifierV1} from "../../src/libraries/verifier/ZkEvmVerifierV1.sol";

import {L2CustomERC20Gateway} from "../../src/L2/gateways/L2CustomERC20Gateway.sol";
import {L2ERC1155Gateway} from "../../src/L2/gateways/L2ERC1155Gateway.sol";
import {L2ERC721Gateway} from "../../src/L2/gateways/L2ERC721Gateway.sol";
import {L2ETHGateway} from "../../src/L2/gateways/L2ETHGateway.sol";
import {L2GatewayRouter} from "../../src/L2/gateways/L2GatewayRouter.sol";
import {L2ScrollMessenger} from "../../src/L2/L2ScrollMessenger.sol";
import {L2StandardERC20Gateway} from "../../src/L2/gateways/L2StandardERC20Gateway.sol";
import {L2WETHGateway} from "../../src/L2/gateways/L2WETHGateway.sol";
import {L1GasPriceOracle} from "../../src/L2/predeploys/L1GasPriceOracle.sol";
import {L2MessageQueue} from "../../src/L2/predeploys/L2MessageQueue.sol";
import {L2TxFeeVault} from "../../src/L2/predeploys/L2TxFeeVault.sol";
import {Whitelist} from "../../src/L2/predeploys/Whitelist.sol";
import {WrappedEther} from "../../src/L2/predeploys/WrappedEther.sol";
import {ScrollStandardERC20} from "../../src/libraries/token/ScrollStandardERC20.sol";
import {ScrollStandardERC20Factory} from "../../src/libraries/token/ScrollStandardERC20Factory.sol";

import {ScrollChainMockFinalize} from "../../src/mocks/ScrollChainMockFinalize.sol";

/// @dev The address of DeterministicDeploymentProxy.
///      See https://github.com/Arachnid/deterministic-deployment-proxy.
address constant DETERMINISTIC_DEPLOYMENT_PROXY_ADDR = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

/// @dev The default deterministic deployment salt prefix.
string constant DEFAULT_DEPLOYMENT_SALT = "ScrollStack";

/// @dev The default minimum withdraw amount configured on L2TxFeeVault.
uint256 constant FEE_VAULT_MIN_WITHDRAW_AMOUNT = 1 ether;

/// @dev The minimum deployer account balance.
uint256 constant MINIMUM_DEPLOYER_BALANCE = 0.1 ether;

// template files
string constant CONFIG_CONTRACTS_TEMPLATE_PATH = "./docker/templates/config-contracts.toml";
string constant GENESIS_JSON_TEMPLATE_PATH = "./docker/templates/genesis.json";
string constant ROLLUP_CONFIG_TEMPLATE_PATH = "./docker/templates/rollup-config.json";
string constant COORDINATOR_CONFIG_TEMPLATE_PATH = "./docker/templates/coordinator-config.json";
string constant CHAIN_MONITOR_CONFIG_TEMPLATE_PATH = "./docker/templates/chain-monitor-config.json";
string constant BRIDGE_HISTORY_CONFIG_TEMPLATE_PATH = "./docker/templates/bridge-history-config.json";
string constant BALANCE_CHECKER_CONFIG_TEMPLATE_PATH = "./docker/templates/balance-checker-config.json";

// input files
string constant CONFIG_PATH = "./volume/config.toml";

// output files
string constant CONFIG_CONTRACTS_PATH = "./volume/config-contracts.toml";
string constant GENESIS_ALLOC_JSON_PATH = "./volume/__genesis-alloc.json";
string constant GENESIS_JSON_PATH = "./volume/genesis.json";
string constant ROLLUP_CONFIG_PATH = "./volume/rollup-config.json";
string constant COORDINATOR_CONFIG_PATH = "./volume/coordinator-config.json";
string constant CHAIN_MONITOR_CONFIG_PATH = "./volume/chain-monitor-config.json";
string constant BRIDGE_HISTORY_CONFIG_PATH = "./volume/bridge-history-config.json";
string constant BALANCE_CHECKER_CONFIG_PATH = "./volume/balance-checker-config.json";
string constant FRONTEND_ENV_PATH = "./volume/.env.frontend";

contract ProxyAdminSetOwner is ProxyAdmin {
    /// @dev allow setting the owner in the constructor, otherwise
    ///      DeterministicDeploymentProxy would become the owner.
    constructor(address owner) {
        _transferOwnership(owner);
    }
}

contract MultipleVersionRollupVerifierSetOwner is MultipleVersionRollupVerifier {
    /// @dev allow setting the owner in the constructor, otherwise
    ///      DeterministicDeploymentProxy would become the owner.
    constructor(
        address owner,
        uint256[] memory _versions,
        address[] memory _verifiers
    ) MultipleVersionRollupVerifier(_versions, _verifiers) {
        _transferOwnership(owner);
    }
}

contract ScrollStandardERC20FactorySetOwner is ScrollStandardERC20Factory {
    /// @dev allow setting the owner in the constructor, otherwise
    ///      DeterministicDeploymentProxy would become the owner.
    constructor(address owner, address _implementation) ScrollStandardERC20Factory(_implementation) {
        _transferOwnership(owner);
    }
}

/// @notice Configuration allows inheriting contracts to read the TOML configuration file.
abstract contract Configuration is Script {
    using stdToml for string;

    /*******************
     * State variables *
     *******************/

    string internal cfg;
    string internal contractsCfg;

    /****************************
     * Configuration parameters *
     ****************************/

    // general
    string internal L1_RPC_ENDPOINT;
    string internal L2_RPC_ENDPOINT;

    uint64 internal CHAIN_ID_L1;
    uint64 internal CHAIN_ID_L2;

    uint256 internal MAX_TX_IN_CHUNK;
    uint256 internal MAX_BLOCK_IN_CHUNK;
    uint256 internal MAX_L1_MESSAGE_GAS_LIMIT;

    uint256 internal L1_CONTRACT_DEPLOYMENT_BLOCK;

    bool internal TEST_ENV_MOCK_FINALIZE_ENABLED;
    uint256 internal TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC;

    // accounts
    uint256 internal DEPLOYER_PRIVATE_KEY;
    uint256 internal L1_COMMIT_SENDER_PRIVATE_KEY;
    uint256 internal L1_FINALIZE_SENDER_PRIVATE_KEY;
    uint256 internal L1_GAS_ORACLE_SENDER_PRIVATE_KEY;
    uint256 internal L2_GAS_ORACLE_SENDER_PRIVATE_KEY;

    address internal DEPLOYER_ADDR;
    address internal L1_COMMIT_SENDER_ADDR;
    address internal L1_FINALIZE_SENDER_ADDR;
    address internal L1_GAS_ORACLE_SENDER_ADDR;
    address internal L2_GAS_ORACLE_SENDER_ADDR;

    address internal OWNER_ADDR;

    address internal L2GETH_SIGNER_0_ADDRESS;

    // db
    string internal SCROLL_DB_CONNECTION_STRING;
    string internal CHAIN_MONITOR_DB_CONNECTION_STRING;
    string internal BRIDGE_HISTORY_DB_CONNECTION_STRING;

    // genesis
    uint256 internal L2_MAX_ETH_SUPPLY;
    uint256 internal L2_DEPLOYER_INITIAL_BALANCE;
    uint256 internal L2_SCROLL_MESSENGER_INITIAL_BALANCE;

    // contracts
    string internal DEPLOYMENT_SALT;

    address internal L1_FEE_VAULT_ADDR;
    address internal L1_PLONK_VERIFIER_ADDR;

    // coordinator
    string internal COORDINATOR_JWT_SECRET_KEY;

    /***************
     * Constructor *
     ***************/

    constructor() {
        if (!vm.exists(CONFIG_CONTRACTS_PATH)) {
            string memory template = vm.readFile(CONFIG_CONTRACTS_TEMPLATE_PATH);
            vm.writeFile(CONFIG_CONTRACTS_PATH, template);
        }

        cfg = vm.readFile(CONFIG_PATH);
        contractsCfg = vm.readFile(CONFIG_CONTRACTS_PATH);

        L1_RPC_ENDPOINT = cfg.readString(".general.L1_RPC_ENDPOINT");
        L2_RPC_ENDPOINT = cfg.readString(".general.L2_RPC_ENDPOINT");

        CHAIN_ID_L1 = uint64(cfg.readUint(".general.CHAIN_ID_L1"));
        CHAIN_ID_L2 = uint64(cfg.readUint(".general.CHAIN_ID_L2"));

        MAX_TX_IN_CHUNK = cfg.readUint(".general.MAX_TX_IN_CHUNK");
        MAX_BLOCK_IN_CHUNK = cfg.readUint(".general.MAX_BLOCK_IN_CHUNK");
        MAX_L1_MESSAGE_GAS_LIMIT = cfg.readUint(".general.MAX_L1_MESSAGE_GAS_LIMIT");

        L1_CONTRACT_DEPLOYMENT_BLOCK = cfg.readUint(".general.L1_CONTRACT_DEPLOYMENT_BLOCK");

        TEST_ENV_MOCK_FINALIZE_ENABLED = cfg.readBool(".general.TEST_ENV_MOCK_FINALIZE_ENABLED");
        TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC = cfg.readUint(".general.TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC");

        DEPLOYER_PRIVATE_KEY = cfg.readUint(".accounts.DEPLOYER_PRIVATE_KEY");
        L1_COMMIT_SENDER_PRIVATE_KEY = cfg.readUint(".accounts.L1_COMMIT_SENDER_PRIVATE_KEY");
        L1_FINALIZE_SENDER_PRIVATE_KEY = cfg.readUint(".accounts.L1_FINALIZE_SENDER_PRIVATE_KEY");
        L1_GAS_ORACLE_SENDER_PRIVATE_KEY = cfg.readUint(".accounts.L1_GAS_ORACLE_SENDER_PRIVATE_KEY");
        L2_GAS_ORACLE_SENDER_PRIVATE_KEY = cfg.readUint(".accounts.L2_GAS_ORACLE_SENDER_PRIVATE_KEY");

        DEPLOYER_ADDR = cfg.readAddress(".accounts.DEPLOYER_ADDR");
        L1_COMMIT_SENDER_ADDR = cfg.readAddress(".accounts.L1_COMMIT_SENDER_ADDR");
        L1_FINALIZE_SENDER_ADDR = cfg.readAddress(".accounts.L1_FINALIZE_SENDER_ADDR");
        L1_GAS_ORACLE_SENDER_ADDR = cfg.readAddress(".accounts.L1_GAS_ORACLE_SENDER_ADDR");
        L2_GAS_ORACLE_SENDER_ADDR = cfg.readAddress(".accounts.L2_GAS_ORACLE_SENDER_ADDR");

        OWNER_ADDR = cfg.readAddress(".accounts.OWNER_ADDR");

        L2GETH_SIGNER_0_ADDRESS = cfg.readAddress(".accounts.L2GETH_SIGNER_0_ADDRESS");

        SCROLL_DB_CONNECTION_STRING = cfg.readString(".db.SCROLL_DB_CONNECTION_STRING");
        CHAIN_MONITOR_DB_CONNECTION_STRING = cfg.readString(".db.CHAIN_MONITOR_DB_CONNECTION_STRING");
        BRIDGE_HISTORY_DB_CONNECTION_STRING = cfg.readString(".db.BRIDGE_HISTORY_DB_CONNECTION_STRING");

        L2_MAX_ETH_SUPPLY = cfg.readUint(".genesis.L2_MAX_ETH_SUPPLY");
        L2_DEPLOYER_INITIAL_BALANCE = cfg.readUint(".genesis.L2_DEPLOYER_INITIAL_BALANCE");
        L2_SCROLL_MESSENGER_INITIAL_BALANCE = L2_MAX_ETH_SUPPLY - L2_DEPLOYER_INITIAL_BALANCE;

        DEPLOYMENT_SALT = cfg.readString(".contracts.DEPLOYMENT_SALT");

        L1_FEE_VAULT_ADDR = cfg.readAddress(".contracts.L1_FEE_VAULT_ADDR");
        L1_PLONK_VERIFIER_ADDR = cfg.readAddress(".contracts.L1_PLONK_VERIFIER_ADDR");

        COORDINATOR_JWT_SECRET_KEY = cfg.readString(".coordinator.COORDINATOR_JWT_SECRET_KEY");

        runSanityCheck();
    }

    /**********************
     * Internal interface *
     **********************/

    /// @dev Ensure that `addr` is not the zero address.
    ///      This helps catch bugs arising from incorrect deployment order.
    function notnull(address addr) internal pure returns (address) {
        require(addr != address(0), "null address");
        return addr;
    }

    function tryGetOverride(string memory name) internal returns (address) {
        address addr;
        string memory key = string(abi.encodePacked(".contracts.overrides.", name));

        if (!vm.keyExistsToml(cfg, key)) {
            return address(0);
        }

        addr = cfg.readAddress(key);

        if (addr.code.length == 0) {
            (VmSafe.CallerMode callerMode, , ) = vm.readCallers();

            // if we're ready to start broadcasting transactions, then we
            // must ensure that the override contract has been deployed.
            if (callerMode == VmSafe.CallerMode.Broadcast || callerMode == VmSafe.CallerMode.RecurrentBroadcast) {
                revert(
                    string(
                        abi.encodePacked(
                            "[ERROR] override ",
                            name,
                            " = ",
                            vm.toString(addr),
                            " not deployed in broadcast mode"
                        )
                    )
                );
            }
        }

        return addr;
    }

    /*********************
     * Private functions *
     *********************/

    function runSanityCheck() private view {
        verifyAccount("DEPLOYER", DEPLOYER_PRIVATE_KEY, DEPLOYER_ADDR);
        verifyAccount("L1_COMMIT_SENDER", L1_COMMIT_SENDER_PRIVATE_KEY, L1_COMMIT_SENDER_ADDR);
        verifyAccount("L1_FINALIZE_SENDER", L1_FINALIZE_SENDER_PRIVATE_KEY, L1_FINALIZE_SENDER_ADDR);
        verifyAccount("L1_GAS_ORACLE_SENDER", L1_GAS_ORACLE_SENDER_PRIVATE_KEY, L1_GAS_ORACLE_SENDER_ADDR);
        verifyAccount("L2_GAS_ORACLE_SENDER", L2_GAS_ORACLE_SENDER_PRIVATE_KEY, L2_GAS_ORACLE_SENDER_ADDR);
    }

    function verifyAccount(
        string memory name,
        uint256 privateKey,
        address addr
    ) private pure {
        if (vm.addr(privateKey) != addr) {
            revert(
                string(
                    abi.encodePacked(
                        "[ERROR] ",
                        name,
                        "_ADDR (",
                        vm.toString(addr),
                        ") does not match ",
                        name,
                        "_PRIVATE_KEY"
                    )
                )
            );
        }
    }
}

/// @notice DeterminsticDeployment provides utilities for deterministic contract deployments.
abstract contract DeterminsticDeployment is Configuration {
    using stdToml for string;

    /*********
     * Types *
     *********/

    enum ScriptMode {
        None,
        LogAddresses,
        WriteConfig,
        VerifyConfig
    }

    /*******************
     * State variables *
     *******************/

    ScriptMode private mode;
    string private saltPrefix;
    bool private skipDeploy;

    /***************
     * Constructor *
     ***************/

    constructor() {
        mode = ScriptMode.None;
        skipDeploy = false;

        // salt prefix used for deterministic deployments
        if (bytes(DEPLOYMENT_SALT).length != 0) {
            saltPrefix = DEPLOYMENT_SALT;
        } else {
            saltPrefix = DEFAULT_DEPLOYMENT_SALT;
        }

        // sanity check: make sure DeterministicDeploymentProxy exists
        if (DETERMINISTIC_DEPLOYMENT_PROXY_ADDR.code.length == 0) {
            revert(
                string(
                    abi.encodePacked(
                        "[ERROR] DeterministicDeploymentProxy (",
                        vm.toString(DETERMINISTIC_DEPLOYMENT_PROXY_ADDR),
                        ") is not available"
                    )
                )
            );
        }
    }

    /**********************
     * Internal interface *
     **********************/

    function setScriptMode(ScriptMode scriptMode) internal {
        mode = scriptMode;
    }

    function setScriptMode(string memory scriptMode) internal {
        if (keccak256(bytes(scriptMode)) == keccak256(bytes("log-addresses"))) {
            mode = ScriptMode.WriteConfig;
        } else if (keccak256(bytes(scriptMode)) == keccak256(bytes("write-config"))) {
            mode = ScriptMode.WriteConfig;
        } else if (keccak256(bytes(scriptMode)) == keccak256(bytes("verify-config"))) {
            mode = ScriptMode.VerifyConfig;
        } else {
            mode = ScriptMode.None;
        }
    }

    function skipDeployment() internal {
        skipDeploy = true;
    }

    function deploy(string memory name, bytes memory codeWithArgs) internal returns (address) {
        return _deploy(name, codeWithArgs);
    }

    function deploy(
        string memory name,
        bytes memory code,
        bytes memory args
    ) internal returns (address) {
        return _deploy(name, abi.encodePacked(code, args));
    }

    function predict(string memory name, bytes memory codeWithArgs) internal view returns (address) {
        return _predict(name, codeWithArgs);
    }

    function predict(
        string memory name,
        bytes memory code,
        bytes memory args
    ) internal view returns (address) {
        return _predict(name, abi.encodePacked(code, args));
    }

    function upgrade(
        address proxyAdminAddr,
        address proxyAddr,
        address implAddr
    ) internal {
        if (!skipDeploy) {
            ProxyAdmin(notnull(proxyAdminAddr)).upgrade(
                ITransparentUpgradeableProxy(notnull(proxyAddr)),
                notnull(implAddr)
            );
        }
    }

    /*********************
     * Private functions *
     *********************/

    function _getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(saltPrefix, name));
    }

    function _deploy(string memory name, bytes memory codeWithArgs) private returns (address) {
        // check override (mainly used with predeploys)
        address addr = tryGetOverride(name);

        if (addr != address(0)) {
            _label(name, addr);
            return addr;
        }

        // predict determinstic deployment address
        addr = _predict(name, codeWithArgs);
        _label(name, addr);

        if (skipDeploy) {
            return addr;
        }

        // revert if the contract is already deployed
        if (addr.code.length > 0) {
            revert(
                string(abi.encodePacked("[ERROR] contract ", name, " (", vm.toString(addr), ") is already deployed"))
            );
        }

        // deploy contract
        bytes32 salt = _getSalt(name);
        bytes memory data = abi.encodePacked(salt, codeWithArgs);
        (bool success, ) = DETERMINISTIC_DEPLOYMENT_PROXY_ADDR.call(data);
        require(success, "call failed");
        require(addr.code.length != 0, "deployment address mismatch");

        return addr;
    }

    function _predict(string memory name, bytes memory codeWithArgs) private view returns (address) {
        bytes32 salt = _getSalt(name);

        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                DETERMINISTIC_DEPLOYMENT_PROXY_ADDR,
                                salt,
                                keccak256(codeWithArgs)
                            )
                        )
                    )
                )
            );
    }

    function _label(string memory name, address addr) internal {
        vm.label(addr, name);

        if (mode == ScriptMode.None) {
            return;
        }

        if (mode == ScriptMode.LogAddresses) {
            console.log(string(abi.encodePacked(name, "_ADDR=", vm.toString(address(addr)))));
            return;
        }

        string memory tomlPath = string(abi.encodePacked(".", name, "_ADDR"));

        if (mode == ScriptMode.WriteConfig) {
            vm.writeToml(vm.toString(addr), CONFIG_CONTRACTS_PATH, tomlPath);
            return;
        }

        if (mode == ScriptMode.VerifyConfig) {
            address expectedAddr = contractsCfg.readAddress(tomlPath);

            if (addr != expectedAddr) {
                revert(
                    string(
                        abi.encodePacked(
                            "[ERROR] unexpected address for ",
                            name,
                            ", expected = ",
                            vm.toString(expectedAddr),
                            " (from toml config), got = ",
                            vm.toString(addr)
                        )
                    )
                );
            }
        }
    }
}

contract DeployScroll is DeterminsticDeployment {
    /*********
     * Types *
     *********/

    enum Layer {
        None,
        L1,
        L2
    }

    /*******************
     * State variables *
     *******************/

    // general configurations
    Layer private broadcastLayer = Layer.None;

    /***********************
     * Contracts to deploy *
     ***********************/

    // L1 addresses
    address internal L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR;
    address internal L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_ENFORCED_TX_GATEWAY_PROXY_ADDR;
    address internal L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_ERC1155_GATEWAY_PROXY_ADDR;
    address internal L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_ERC721_GATEWAY_PROXY_ADDR;
    address internal L1_ETH_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_ETH_GATEWAY_PROXY_ADDR;
    address internal L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR;
    address internal L1_GATEWAY_ROUTER_PROXY_ADDR;
    address internal L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR;
    address internal L1_MESSAGE_QUEUE_PROXY_ADDR;
    address internal L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR;
    address internal L1_PROXY_ADMIN_ADDR;
    address internal L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR;
    address internal L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR;
    address internal L1_SCROLL_CHAIN_PROXY_ADDR;
    address internal L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR;
    address internal L1_SCROLL_MESSENGER_PROXY_ADDR;
    address internal L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR;
    address internal L1_WETH_ADDR;
    address internal L1_WETH_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_WETH_GATEWAY_PROXY_ADDR;
    address internal L1_WHITELIST_ADDR;
    address internal L1_ZKEVM_VERIFIER_V1_ADDR;
    address internal L2_GAS_PRICE_ORACLE_IMPLEMENTATION_ADDR;
    address internal L2_GAS_PRICE_ORACLE_PROXY_ADDR;

    // L2 addresses
    address internal L1_GAS_PRICE_ORACLE_ADDR;
    address internal L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR;
    address internal L2_ERC1155_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_ERC1155_GATEWAY_PROXY_ADDR;
    address internal L2_ERC721_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_ERC721_GATEWAY_PROXY_ADDR;
    address internal L2_ETH_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_ETH_GATEWAY_PROXY_ADDR;
    address internal L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR;
    address internal L2_GATEWAY_ROUTER_PROXY_ADDR;
    address internal L2_MESSAGE_QUEUE_ADDR;
    address internal L2_PROXY_ADMIN_ADDR;
    address internal L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR;
    address internal L2_SCROLL_MESSENGER_IMPLEMENTATION_ADDR;
    address internal L2_SCROLL_MESSENGER_PROXY_ADDR;
    address internal L2_SCROLL_STANDARD_ERC20_ADDR;
    address internal L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR;
    address internal L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR;
    address internal L2_TX_FEE_VAULT_ADDR;
    address internal L2_WETH_ADDR;
    address internal L2_WETH_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_WETH_GATEWAY_PROXY_ADDR;
    address internal L2_WHITELIST_ADDR;

    /*************
     * Utilities *
     *************/

    /// @dev Only broadcast code block if we run the script on the specified layer.
    modifier broadcast(Layer layer) {
        if (broadcastLayer == layer) {
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        } else {
            // make sure we use the correct sender in simulation
            vm.startPrank(DEPLOYER_ADDR);
        }

        _;

        if (broadcastLayer == layer) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }

    /// @dev Only execute block if we run the script on the specified layer.
    modifier only(Layer layer) {
        if (broadcastLayer != layer) {
            return;
        }
        _;
    }

    /***************
     * Entry point *
     ***************/

    function run(string memory layer, string memory scriptMode) public {
        broadcastLayer = parseLayer(layer);
        setScriptMode(scriptMode);

        checkDeployerBalance();
        deployAllContracts();
        initializeL1Contracts();
        initializeL2Contracts();
    }

    /**********************
     * Internal interface *
     **********************/

    function predictAllContracts() internal {
        skipDeployment();
        deployAllContracts();
    }

    /*********************
     * Private functions *
     *********************/

    function parseLayer(string memory raw) private pure returns (Layer) {
        if (keccak256(bytes(raw)) == keccak256(bytes("L1"))) {
            return Layer.L1;
        } else if (keccak256(bytes(raw)) == keccak256(bytes("L2"))) {
            return Layer.L2;
        } else {
            return Layer.None;
        }
    }

    function checkDeployerBalance() private view {
        // ignore balance during simulation
        if (broadcastLayer == Layer.None) {
            return;
        }

        if (DEPLOYER_ADDR.balance < MINIMUM_DEPLOYER_BALANCE) {
            revert(
                string(
                    abi.encodePacked(
                        "[ERROR] insufficient funds on deployer account (",
                        vm.toString(DEPLOYER_ADDR),
                        ")"
                    )
                )
            );
        }
    }

    function deployAllContracts() private {
        deployL1Contracts1stPass();
        deployL2Contracts1stPass();
        deployL1Contracts2ndPass();
        deployL2Contracts2ndPass();
    }

    // @notice deployL1Contracts1stPass deploys L1 contracts whose initialization does not depend on any L2 addresses.
    function deployL1Contracts1stPass() private broadcast(Layer.L1) {
        deployL1Weth();
        deployL1ProxyAdmin();
        deployL1PlaceHolder();
        deployL1Whitelist();
        deployL2GasPriceOracle();
        deployL1ScrollChainProxy();
        deployL1ScrollMessengerProxy();
        deployL1EnforcedTxGateway();
        deployL1ZkEvmVerifierV1();
        deployL1MultipleVersionRollupVerifier();
        deployL1MessageQueue();
        deployL1ScrollChain();
        deployL1GatewayRouter();
        deployL1ETHGatewayProxy();
        deployL1WETHGatewayProxy();
        deployL1StandardERC20GatewayProxy();
        deployL1CustomERC20GatewayProxy();
        deployL1ERC721GatewayProxy();
        deployL1ERC1155GatewayProxy();
    }

    // @notice deployL2Contracts1stPass deploys L2 contracts whose initialization does not depend on any L1 addresses.
    function deployL2Contracts1stPass() private broadcast(Layer.L2) {
        deployL2MessageQueue();
        deployL1GasPriceOracle();
        deployL2Whitelist();
        deployL2Weth();
        deployTxFeeVault();
        deployL2ProxyAdmin();
        deployL2PlaceHolder();
        deployL2ScrollMessengerProxy();
        deployL2ETHGatewayProxy();
        deployL2WETHGatewayProxy();
        deployL2StandardERC20GatewayProxy();
        deployL2CustomERC20GatewayProxy();
        deployL2ERC721GatewayProxy();
        deployL2ERC1155GatewayProxy();
        deployScrollStandardERC20Factory();
    }

    // @notice deployL1Contracts2ndPass deploys L1 contracts whose initialization depends on some L2 addresses.
    function deployL1Contracts2ndPass() private broadcast(Layer.L1) {
        deployL1ScrollMessenger();
        deployL1StandardERC20Gateway();
        deployL1ETHGateway();
        deployL1WETHGateway();
        deployL1CustomERC20Gateway();
        deployL1ERC721Gateway();
        deployL1ERC1155Gateway();
    }

    // @notice deployL2Contracts2ndPass deploys L2 contracts whose initialization depends on some L1 addresses.
    function deployL2Contracts2ndPass() private broadcast(Layer.L2) {
        // upgradable
        deployL2ScrollMessenger();
        deployL2GatewayRouter();
        deployL2StandardERC20Gateway();
        deployL2ETHGateway();
        deployL2WETHGateway();
        deployL2CustomERC20Gateway();
        deployL2ERC721Gateway();
        deployL2ERC1155Gateway();
    }

    // @notice initializeL1Contracts initializes contracts deployed on L1.
    function initializeL1Contracts() private broadcast(Layer.L1) only(Layer.L1) {
        initializeScrollChain();
        initializeL2GasPriceOracle();
        initializeL1MessageQueue();
        initializeL1ScrollMessenger();
        initializeEnforcedTxGateway();
        initializeL1GatewayRouter();
        initializeL1CustomERC20Gateway();
        initializeL1ERC1155Gateway();
        initializeL1ERC721Gateway();
        initializeL1ETHGateway();
        initializeL1StandardERC20Gateway();
        initializeL1WETHGateway();
        initializeL1Whitelist();

        transferL1ContractOwnership();
    }

    // @notice initializeL2Contracts initializes contracts deployed on L2.
    function initializeL2Contracts() private broadcast(Layer.L2) only(Layer.L2) {
        initializeL2MessageQueue();
        initializeL2TxFeeVault();
        initializeL1GasPriceOracle();
        initializeL2ScrollMessenger();
        initializeL2GatewayRouter();
        initializeL2CustomERC20Gateway();
        initializeL2ERC1155Gateway();
        initializeL2ERC721Gateway();
        initializeL2ETHGateway();
        initializeL2StandardERC20Gateway();
        initializeL2WETHGateway();
        initializeScrollStandardERC20Factory();
        initializeL2Whitelist();

        transferL2ContractOwnership();
    }

    /***************************
     * L1: 1st pass deployment *
     ***************************/

    function deployL1Weth() private {
        L1_WETH_ADDR = deploy("L1_WETH", type(WrappedEther).creationCode);
    }

    function deployL1ProxyAdmin() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L1_PROXY_ADMIN_ADDR = deploy("L1_PROXY_ADMIN", type(ProxyAdminSetOwner).creationCode, args);
    }

    function deployL1PlaceHolder() private {
        L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR = deploy(
            "L1_PROXY_IMPLEMENTATION_PLACEHOLDER",
            type(EmptyContract).creationCode
        );
    }

    function deployL1Whitelist() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L1_WHITELIST_ADDR = deploy("L1_WHITELIST", type(Whitelist).creationCode, args);
    }

    function deployL2GasPriceOracle() private {
        L2_GAS_PRICE_ORACLE_IMPLEMENTATION_ADDR = deploy(
            "L2_GAS_PRICE_ORACLE_IMPLEMENTATION",
            type(L2GasPriceOracle).creationCode
        );

        bytes memory args = abi.encode(
            notnull(L2_GAS_PRICE_ORACLE_IMPLEMENTATION_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_GAS_PRICE_ORACLE_PROXY_ADDR = deploy(
            "L2_GAS_PRICE_ORACLE_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ScrollChainProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_SCROLL_CHAIN_PROXY_ADDR = deploy(
            "L1_SCROLL_CHAIN_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ScrollMessengerProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_SCROLL_MESSENGER_PROXY_ADDR = deploy(
            "L1_SCROLL_MESSENGER_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1EnforcedTxGateway() private {
        L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION",
            type(EnforcedTxGateway).creationCode
        );

        bytes memory args = abi.encode(
            notnull(L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_ENFORCED_TX_GATEWAY_PROXY_ADDR = deploy(
            "L1_ENFORCED_TX_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ZkEvmVerifierV1() private {
        bytes memory args = abi.encode(notnull(L1_PLONK_VERIFIER_ADDR));
        L1_ZKEVM_VERIFIER_V1_ADDR = deploy("L1_ZKEVM_VERIFIER_V1", type(ZkEvmVerifierV1).creationCode, args);
    }

    function deployL1MultipleVersionRollupVerifier() private {
        uint256[] memory _versions = new uint256[](1);
        address[] memory _verifiers = new address[](1);
        _versions[0] = 1;
        _verifiers[0] = notnull(L1_ZKEVM_VERIFIER_V1_ADDR);

        bytes memory args = abi.encode(DEPLOYER_ADDR, _versions, _verifiers);

        L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR = deploy(
            "L1_MULTIPLE_VERSION_ROLLUP_VERIFIER",
            type(MultipleVersionRollupVerifierSetOwner).creationCode,
            args
        );
    }

    function deployL1MessageQueue() private {
        bytes memory args = abi.encode(
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L1_SCROLL_CHAIN_PROXY_ADDR),
            notnull(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR)
        );

        L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR = deploy(
            "L1_MESSAGE_QUEUE_IMPLEMENTATION",
            type(L1MessageQueueWithGasPriceOracle).creationCode,
            args
        );

        bytes memory args2 = abi.encode(
            notnull(L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_MESSAGE_QUEUE_PROXY_ADDR = deploy(
            "L1_MESSAGE_QUEUE_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args2
        );
    }

    function deployL1ScrollChain() private {
        bytes memory args = abi.encode(
            CHAIN_ID_L2,
            notnull(L1_MESSAGE_QUEUE_PROXY_ADDR),
            notnull(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR)
        );

        bytes memory creationCode = type(ScrollChain).creationCode;

        if (TEST_ENV_MOCK_FINALIZE_ENABLED) {
            creationCode = type(ScrollChainMockFinalize).creationCode;
        }

        L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR = deploy("L1_SCROLL_CHAIN_IMPLEMENTATION", creationCode, args);

        upgrade(L1_PROXY_ADMIN_ADDR, L1_SCROLL_CHAIN_PROXY_ADDR, L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR);
    }

    function deployL1GatewayRouter() private {
        L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR = deploy(
            "L1_GATEWAY_ROUTER_IMPLEMENTATION",
            type(L1GatewayRouter).creationCode
        );

        bytes memory args = abi.encode(
            notnull(L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_GATEWAY_ROUTER_PROXY_ADDR = deploy(
            "L1_GATEWAY_ROUTER_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ETHGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_ETH_GATEWAY_PROXY_ADDR = deploy(
            "L1_ETH_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1WETHGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_WETH_GATEWAY_PROXY_ADDR = deploy(
            "L1_WETH_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1StandardERC20GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = deploy(
            "L1_STANDARD_ERC20_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1CustomERC20GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = deploy(
            "L1_CUSTOM_ERC20_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ERC721GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_ERC721_GATEWAY_PROXY_ADDR = deploy(
            "L1_ERC721_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ERC1155GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_ERC1155_GATEWAY_PROXY_ADDR = deploy(
            "L1_ERC1155_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    /***************************
     * L2: 1st pass deployment *
     ***************************/

    function deployL2MessageQueue() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L2_MESSAGE_QUEUE_ADDR = deploy("L2_MESSAGE_QUEUE", type(L2MessageQueue).creationCode, args);
    }

    function deployL1GasPriceOracle() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L1_GAS_PRICE_ORACLE_ADDR = deploy("L1_GAS_PRICE_ORACLE", type(L1GasPriceOracle).creationCode, args);
    }

    function deployL2Whitelist() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L2_WHITELIST_ADDR = deploy("L2_WHITELIST", type(Whitelist).creationCode, args);
    }

    function deployL2Weth() private {
        L2_WETH_ADDR = deploy("L2_WETH", type(WrappedEther).creationCode);
    }

    function deployTxFeeVault() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR, L1_FEE_VAULT_ADDR, FEE_VAULT_MIN_WITHDRAW_AMOUNT);
        L2_TX_FEE_VAULT_ADDR = deploy("L2_TX_FEE_VAULT", type(L2TxFeeVault).creationCode, args);
    }

    function deployL2ProxyAdmin() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L2_PROXY_ADMIN_ADDR = deploy("L2_PROXY_ADMIN", type(ProxyAdminSetOwner).creationCode, args);
    }

    function deployL2PlaceHolder() private {
        L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR = deploy(
            "L2_PROXY_IMPLEMENTATION_PLACEHOLDER",
            type(EmptyContract).creationCode
        );
    }

    function deployL2ScrollMessengerProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_SCROLL_MESSENGER_PROXY_ADDR = deploy(
            "L2_SCROLL_MESSENGER_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2StandardERC20GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR = deploy(
            "L2_STANDARD_ERC20_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2ETHGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_ETH_GATEWAY_PROXY_ADDR = deploy(
            "L2_ETH_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2WETHGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_WETH_GATEWAY_PROXY_ADDR = deploy(
            "L2_WETH_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2CustomERC20GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = deploy(
            "L2_CUSTOM_ERC20_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2ERC721GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_ERC721_GATEWAY_PROXY_ADDR = deploy(
            "L2_ERC721_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2ERC1155GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_ERC1155_GATEWAY_PROXY_ADDR = deploy(
            "L2_ERC1155_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployScrollStandardERC20Factory() private {
        L2_SCROLL_STANDARD_ERC20_ADDR = deploy("L2_SCROLL_STANDARD_ERC20", type(ScrollStandardERC20).creationCode);
        bytes memory args = abi.encode(DEPLOYER_ADDR, notnull(L2_SCROLL_STANDARD_ERC20_ADDR));

        L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR = deploy(
            "L2_SCROLL_STANDARD_ERC20_FACTORY",
            type(ScrollStandardERC20FactorySetOwner).creationCode,
            args
        );
    }

    /***************************
     * L1: 2nd pass deployment *
     ***************************/

    function deployL1ScrollMessenger() private {
        bytes memory args = abi.encode(
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L1_SCROLL_CHAIN_PROXY_ADDR),
            notnull(L1_MESSAGE_QUEUE_PROXY_ADDR)
        );

        L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR = deploy(
            "L1_SCROLL_MESSENGER_IMPLEMENTATION",
            type(L1ScrollMessenger).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_SCROLL_MESSENGER_PROXY_ADDR, L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR);
    }

    function deployL1ETHGateway() private {
        bytes memory args = abi.encode(
            notnull(L2_ETH_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L1_ETH_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_ETH_GATEWAY_IMPLEMENTATION",
            type(L1ETHGateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_ETH_GATEWAY_PROXY_ADDR, L1_ETH_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1WETHGateway() private {
        bytes memory args = abi.encode(
            notnull(L1_WETH_ADDR),
            notnull(L2_WETH_ADDR),
            notnull(L2_WETH_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L1_WETH_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_WETH_GATEWAY_IMPLEMENTATION",
            type(L1WETHGateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_WETH_GATEWAY_PROXY_ADDR, L1_WETH_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1StandardERC20Gateway() private {
        bytes memory args = abi.encode(
            notnull(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR)
        );

        L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION",
            type(L1StandardERC20Gateway).creationCode,
            args
        );

        upgrade(
            L1_PROXY_ADMIN_ADDR,
            L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR,
            L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR
        );
    }

    function deployL1CustomERC20Gateway() private {
        bytes memory args = abi.encode(
            notnull(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION",
            type(L1CustomERC20Gateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR, L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1ERC721Gateway() private {
        bytes memory args = abi.encode(notnull(L2_ERC721_GATEWAY_PROXY_ADDR), notnull(L1_SCROLL_MESSENGER_PROXY_ADDR));

        L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_ERC721_GATEWAY_IMPLEMENTATION",
            type(L1ERC721Gateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_ERC721_GATEWAY_PROXY_ADDR, L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1ERC1155Gateway() private {
        bytes memory args = abi.encode(notnull(L2_ERC1155_GATEWAY_PROXY_ADDR), notnull(L1_SCROLL_MESSENGER_PROXY_ADDR));

        L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_ERC1155_GATEWAY_IMPLEMENTATION",
            type(L1ERC1155Gateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_ERC1155_GATEWAY_PROXY_ADDR, L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR);
    }

    /***************************
     * L2: 2nd pass deployment *
     ***************************/

    function deployL2ScrollMessenger() private {
        bytes memory args = abi.encode(notnull(L1_SCROLL_MESSENGER_PROXY_ADDR), notnull(L2_MESSAGE_QUEUE_ADDR));

        L2_SCROLL_MESSENGER_IMPLEMENTATION_ADDR = deploy(
            "L2_SCROLL_MESSENGER_IMPLEMENTATION",
            type(L2ScrollMessenger).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_SCROLL_MESSENGER_PROXY_ADDR, L2_SCROLL_MESSENGER_IMPLEMENTATION_ADDR);
    }

    function deployL2GatewayRouter() private {
        L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR = deploy(
            "L2_GATEWAY_ROUTER_IMPLEMENTATION",
            type(L2GatewayRouter).creationCode
        );

        bytes memory args = abi.encode(
            notnull(L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_GATEWAY_ROUTER_PROXY_ADDR = deploy(
            "L2_GATEWAY_ROUTER_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2StandardERC20Gateway() private {
        bytes memory args = abi.encode(
            notnull(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR)
        );

        L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION",
            type(L2StandardERC20Gateway).creationCode,
            args
        );

        upgrade(
            L2_PROXY_ADMIN_ADDR,
            L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR,
            L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR
        );
    }

    function deployL2ETHGateway() private {
        bytes memory args = abi.encode(
            notnull(L1_ETH_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L2_ETH_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_ETH_GATEWAY_IMPLEMENTATION",
            type(L2ETHGateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_ETH_GATEWAY_PROXY_ADDR, L2_ETH_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL2WETHGateway() private {
        bytes memory args = abi.encode(
            notnull(L2_WETH_ADDR),
            notnull(L1_WETH_ADDR),
            notnull(L1_WETH_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L2_WETH_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_WETH_GATEWAY_IMPLEMENTATION",
            type(L2WETHGateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_WETH_GATEWAY_PROXY_ADDR, L2_WETH_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL2CustomERC20Gateway() private {
        bytes memory args = abi.encode(
            notnull(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION",
            type(L2CustomERC20Gateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR, L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL2ERC721Gateway() private {
        bytes memory args = abi.encode(notnull(L1_ERC721_GATEWAY_PROXY_ADDR), notnull(L2_SCROLL_MESSENGER_PROXY_ADDR));

        L2_ERC721_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_ERC721_GATEWAY_IMPLEMENTATION",
            type(L2ERC721Gateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_ERC721_GATEWAY_PROXY_ADDR, L2_ERC721_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL2ERC1155Gateway() private {
        bytes memory args = abi.encode(notnull(L1_ERC1155_GATEWAY_PROXY_ADDR), notnull(L2_SCROLL_MESSENGER_PROXY_ADDR));

        L2_ERC1155_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_ERC1155_GATEWAY_IMPLEMENTATION",
            type(L2ERC1155Gateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_ERC1155_GATEWAY_PROXY_ADDR, L2_ERC1155_GATEWAY_IMPLEMENTATION_ADDR);
    }

    /**********************
     * L1: initialization *
     **********************/

    function initializeScrollChain() private {
        ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).initialize(
            notnull(L1_MESSAGE_QUEUE_PROXY_ADDR),
            notnull(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR),
            MAX_TX_IN_CHUNK
        );

        ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).addSequencer(L1_COMMIT_SENDER_ADDR);
        ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).addProver(L1_FINALIZE_SENDER_ADDR);
    }

    function initializeL2GasPriceOracle() private {
        L2GasPriceOracle(L2_GAS_PRICE_ORACLE_PROXY_ADDR).initialize(
            21000, // _txGas
            53000, // _txGasContractCreation
            4, // _zeroGas
            16 // _nonZeroGas
        );

        L2GasPriceOracle(L2_GAS_PRICE_ORACLE_PROXY_ADDR).updateWhitelist(L1_WHITELIST_ADDR);
    }

    function initializeL1MessageQueue() private {
        L1MessageQueueWithGasPriceOracle(L1_MESSAGE_QUEUE_PROXY_ADDR).initialize(
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L1_SCROLL_CHAIN_PROXY_ADDR),
            notnull(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR),
            notnull(L2_GAS_PRICE_ORACLE_PROXY_ADDR),
            MAX_L1_MESSAGE_GAS_LIMIT
        );

        L1MessageQueueWithGasPriceOracle(L1_MESSAGE_QUEUE_PROXY_ADDR).initializeV2();
    }

    function initializeL1ScrollMessenger() private {
        L1ScrollMessenger(payable(L1_SCROLL_MESSENGER_PROXY_ADDR)).initialize(
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L1_FEE_VAULT_ADDR),
            notnull(L1_SCROLL_CHAIN_PROXY_ADDR),
            notnull(L1_MESSAGE_QUEUE_PROXY_ADDR)
        );
    }

    function initializeEnforcedTxGateway() private {
        EnforcedTxGateway(payable(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR)).initialize(
            notnull(L1_MESSAGE_QUEUE_PROXY_ADDR),
            notnull(L1_FEE_VAULT_ADDR)
        );

        // disable gateway
        EnforcedTxGateway(payable(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR)).setPause(true);
    }

    function initializeL1GatewayRouter() private {
        L1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).initialize(
            notnull(L1_ETH_GATEWAY_PROXY_ADDR),
            notnull(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR)
        );
    }

    function initializeL1CustomERC20Gateway() private {
        L1CustomERC20Gateway(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR).initialize(
            notnull(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );
    }

    function initializeL1ERC1155Gateway() private {
        L1ERC1155Gateway(L1_ERC1155_GATEWAY_PROXY_ADDR).initialize(
            notnull(L2_ERC1155_GATEWAY_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );
    }

    function initializeL1ERC721Gateway() private {
        L1ERC721Gateway(L1_ERC721_GATEWAY_PROXY_ADDR).initialize(
            notnull(L2_ERC721_GATEWAY_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );
    }

    function initializeL1ETHGateway() private {
        L1ETHGateway(L1_ETH_GATEWAY_PROXY_ADDR).initialize(
            notnull(L2_ETH_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );
    }

    function initializeL1StandardERC20Gateway() private {
        L1StandardERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).initialize(
            notnull(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR)
        );
    }

    function initializeL1WETHGateway() private {
        L1WETHGateway(payable(L1_WETH_GATEWAY_PROXY_ADDR)).initialize(
            notnull(L2_WETH_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );

        // set WETH gateway in router
        {
            address[] memory _tokens = new address[](1);
            _tokens[0] = notnull(L1_WETH_ADDR);
            address[] memory _gateways = new address[](1);
            _gateways[0] = notnull(L1_WETH_GATEWAY_PROXY_ADDR);
            L1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).setERC20Gateway(_tokens, _gateways);
        }
    }

    function initializeL1Whitelist() private {
        address[] memory accounts = new address[](1);
        accounts[0] = L1_GAS_ORACLE_SENDER_ADDR;
        Whitelist(L1_WHITELIST_ADDR).updateWhitelistStatus(accounts, true);
    }

    function transferL1ContractOwnership() private {
        if (DEPLOYER_ADDR == OWNER_ADDR) {
            return;
        }

        Ownable(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_ERC1155_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_ERC721_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_ETH_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_GATEWAY_ROUTER_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_MESSAGE_QUEUE_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_SCROLL_MESSENGER_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_WETH_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_GAS_PRICE_ORACLE_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_PROXY_ADMIN_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_SCROLL_CHAIN_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L1_WHITELIST_ADDR).transferOwnership(OWNER_ADDR);
    }

    /**********************
     * L2: initialization *
     **********************/

    function initializeL2MessageQueue() private {
        L2MessageQueue(L2_MESSAGE_QUEUE_ADDR).initialize(notnull(L2_SCROLL_MESSENGER_PROXY_ADDR));
    }

    function initializeL2TxFeeVault() private {
        L2TxFeeVault(payable(L2_TX_FEE_VAULT_ADDR)).updateMessenger(notnull(L2_SCROLL_MESSENGER_PROXY_ADDR));
    }

    function initializeL1GasPriceOracle() private {
        L1GasPriceOracle(L1_GAS_PRICE_ORACLE_ADDR).updateWhitelist(notnull(L2_WHITELIST_ADDR));
    }

    function initializeL2ScrollMessenger() private {
        L2ScrollMessenger(payable(L2_SCROLL_MESSENGER_PROXY_ADDR)).initialize(notnull(L1_SCROLL_MESSENGER_PROXY_ADDR));
    }

    function initializeL2GatewayRouter() private {
        L2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).initialize(
            notnull(L2_ETH_GATEWAY_PROXY_ADDR),
            notnull(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR)
        );
    }

    function initializeL2CustomERC20Gateway() private {
        L2CustomERC20Gateway(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR).initialize(
            notnull(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );
    }

    function initializeL2ERC1155Gateway() private {
        L2ERC1155Gateway(L2_ERC1155_GATEWAY_PROXY_ADDR).initialize(
            notnull(L1_ERC1155_GATEWAY_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );
    }

    function initializeL2ERC721Gateway() private {
        L2ERC721Gateway(L2_ERC721_GATEWAY_PROXY_ADDR).initialize(
            notnull(L1_ERC721_GATEWAY_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );
    }

    function initializeL2ETHGateway() private {
        L2ETHGateway(L2_ETH_GATEWAY_PROXY_ADDR).initialize(
            notnull(L1_ETH_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );
    }

    function initializeL2StandardERC20Gateway() private {
        L2StandardERC20Gateway(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR).initialize(
            notnull(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR)
        );
    }

    function initializeL2WETHGateway() private {
        L2WETHGateway(payable(L2_WETH_GATEWAY_PROXY_ADDR)).initialize(
            notnull(L1_WETH_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );

        // set WETH gateway in router
        {
            address[] memory _tokens = new address[](1);
            _tokens[0] = notnull(L2_WETH_ADDR);
            address[] memory _gateways = new address[](1);
            _gateways[0] = notnull(L2_WETH_GATEWAY_PROXY_ADDR);
            L2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).setERC20Gateway(_tokens, _gateways);
        }
    }

    function initializeScrollStandardERC20Factory() private {
        ScrollStandardERC20Factory(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR).transferOwnership(
            notnull(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR)
        );
    }

    function initializeL2Whitelist() private {
        address[] memory accounts = new address[](1);
        accounts[0] = L2_GAS_ORACLE_SENDER_ADDR;
        Whitelist(L2_WHITELIST_ADDR).updateWhitelistStatus(accounts, true);
    }

    function transferL2ContractOwnership() private {
        if (DEPLOYER_ADDR == OWNER_ADDR) {
            return;
        }

        Ownable(L1_GAS_PRICE_ORACLE_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_ERC1155_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_ERC721_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_ETH_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_GATEWAY_ROUTER_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_MESSAGE_QUEUE_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_SCROLL_MESSENGER_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_TX_FEE_VAULT_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_WETH_GATEWAY_PROXY_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_PROXY_ADMIN_ADDR).transferOwnership(OWNER_ADDR);
        Ownable(L2_WHITELIST_ADDR).transferOwnership(OWNER_ADDR);
    }
}

contract GenerateGenesis is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        setScriptMode(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateGenesisAlloc();
        generateGenesisJson();

        // clean up temporary files
        vm.removeFile(GENESIS_ALLOC_JSON_PATH);
    }

    /*********************
     * Private functions *
     *********************/

    function generateGenesisAlloc() private {
        if (vm.exists(GENESIS_ALLOC_JSON_PATH)) {
            vm.removeFile(GENESIS_ALLOC_JSON_PATH);
        }

        // Scroll predeploys
        setL2MessageQueue();
        setL1GasPriceOracle();
        setL2Whitelist();
        setL2Weth();
        setL2FeeVault();

        // other predeploys
        setDeterministicDeploymentProxy();

        // reset sender
        vm.resetNonce(msg.sender);

        // prefunded accounts
        setL2ScrollMessenger();
        setL2Deployer();

        // write to file
        vm.dumpState(GENESIS_ALLOC_JSON_PATH);
        sortJsonByKeys(GENESIS_ALLOC_JSON_PATH);
    }

    function setL2MessageQueue() internal {
        address predeployAddr = tryGetOverride("L2_MESSAGE_QUEUE");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        L2MessageQueue _queue = new L2MessageQueue(OWNER_ADDR);
        vm.etch(predeployAddr, address(_queue).code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000052";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_queue), _ownerSlot));

        // reset so its not included state dump
        vm.etch(address(_queue), "");
        vm.resetNonce(address(_queue));
    }

    function setL1GasPriceOracle() internal {
        address predeployAddr = tryGetOverride("L1_GAS_PRICE_ORACLE");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        L1GasPriceOracle _oracle = new L1GasPriceOracle(OWNER_ADDR);
        vm.etch(predeployAddr, address(_oracle).code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000000";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_oracle), _ownerSlot));

        bytes32 _isCurieSlot = hex"0000000000000000000000000000000000000000000000000000000000000008";
        vm.store(predeployAddr, _isCurieSlot, bytes32(uint256(1)));

        // reset so its not included state dump
        vm.etch(address(_oracle), "");
        vm.resetNonce(address(_oracle));
    }

    function setL2Whitelist() internal {
        address predeployAddr = tryGetOverride("L2_WHITELIST");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        Whitelist _whitelist = new Whitelist(OWNER_ADDR);
        vm.etch(predeployAddr, address(_whitelist).code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000000";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_whitelist), _ownerSlot));

        // reset so its not included state dump
        vm.etch(address(_whitelist), "");
        vm.resetNonce(address(_whitelist));
    }

    function setL2Weth() internal {
        address predeployAddr = tryGetOverride("L2_WETH");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        WrappedEther _weth = new WrappedEther();
        vm.etch(predeployAddr, address(_weth).code);

        // set storage
        bytes32 _nameSlot = hex"0000000000000000000000000000000000000000000000000000000000000003";
        vm.store(predeployAddr, _nameSlot, vm.load(address(_weth), _nameSlot));

        bytes32 _symbolSlot = hex"0000000000000000000000000000000000000000000000000000000000000004";
        vm.store(predeployAddr, _symbolSlot, vm.load(address(_weth), _symbolSlot));

        // reset so its not included state dump
        vm.etch(address(_weth), "");
        vm.resetNonce(address(_weth));
    }

    function setL2FeeVault() internal {
        address predeployAddr = tryGetOverride("L2_TX_FEE_VAULT");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        L2TxFeeVault _vault = new L2TxFeeVault(OWNER_ADDR, L1_FEE_VAULT_ADDR, FEE_VAULT_MIN_WITHDRAW_AMOUNT);
        vm.etch(predeployAddr, address(_vault).code);

        vm.prank(OWNER_ADDR);
        _vault.updateMessenger(L2_SCROLL_MESSENGER_PROXY_ADDR);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000000";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_vault), _ownerSlot));

        bytes32 _minWithdrawAmountSlot = hex"0000000000000000000000000000000000000000000000000000000000000001";
        vm.store(predeployAddr, _minWithdrawAmountSlot, vm.load(address(_vault), _minWithdrawAmountSlot));

        bytes32 _messengerSlot = hex"0000000000000000000000000000000000000000000000000000000000000002";
        vm.store(predeployAddr, _messengerSlot, vm.load(address(_vault), _messengerSlot));

        bytes32 _recipientSlot = hex"0000000000000000000000000000000000000000000000000000000000000003";
        vm.store(predeployAddr, _recipientSlot, vm.load(address(_vault), _recipientSlot));

        // reset so its not included state dump
        vm.etch(address(_vault), "");
        vm.resetNonce(address(_vault));
    }

    function setDeterministicDeploymentProxy() internal {
        bytes
            memory code = hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
        vm.etch(DETERMINISTIC_DEPLOYMENT_PROXY_ADDR, code);
    }

    function setL2ScrollMessenger() internal {
        vm.deal(L2_SCROLL_MESSENGER_PROXY_ADDR, L2_SCROLL_MESSENGER_INITIAL_BALANCE);
    }

    function setL2Deployer() internal {
        vm.deal(OWNER_ADDR, L2_DEPLOYER_INITIAL_BALANCE);
    }

    function generateGenesisJson() private {
        // initialize template file
        if (vm.exists(GENESIS_JSON_PATH)) {
            vm.removeFile(GENESIS_JSON_PATH);
        }

        string memory template = vm.readFile(GENESIS_JSON_TEMPLATE_PATH);
        vm.writeFile(GENESIS_JSON_PATH, template);

        // general config
        vm.writeJson(vm.toString(CHAIN_ID_L2), GENESIS_JSON_PATH, ".config.chainId");

        uint256 timestamp = vm.unixTime() / 1000;
        vm.writeJson(vm.toString(bytes32(timestamp)), GENESIS_JSON_PATH, ".timestamp");

        string memory extraData = string(
            abi.encodePacked(
                "0x0000000000000000000000000000000000000000000000000000000000000000",
                vm.replace(vm.toString(L2GETH_SIGNER_0_ADDRESS), "0x", ""),
                "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            )
        );

        vm.writeJson(extraData, GENESIS_JSON_PATH, ".extraData");

        // scroll-specific config
        vm.writeJson(vm.toString(MAX_TX_IN_CHUNK), GENESIS_JSON_PATH, ".config.scroll.maxTxPerBlock");
        vm.writeJson(vm.toString(L2_TX_FEE_VAULT_ADDR), GENESIS_JSON_PATH, ".config.scroll.feeVaultAddress");

        // serialize explicitly as string, otherwise foundry will serialize it as number
        string memory l1ChainId = string(abi.encodePacked('"', vm.toString(CHAIN_ID_L1), '"'));
        vm.writeJson(l1ChainId, GENESIS_JSON_PATH, ".config.scroll.l1Config.l1ChainId");

        vm.writeJson(
            vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR),
            GENESIS_JSON_PATH,
            ".config.scroll.l1Config.l1MessageQueueAddress"
        );

        vm.writeJson(
            vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR),
            GENESIS_JSON_PATH,
            ".config.scroll.l1Config.scrollChainAddress"
        );

        // predeploys and prefunded accounts
        string memory alloc = vm.readFile(GENESIS_ALLOC_JSON_PATH);
        vm.writeJson(alloc, GENESIS_JSON_PATH, ".alloc");
    }

    /// @notice Sorts the allocs by address
    // source: https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/scripts/L2Genesis.s.sol
    function sortJsonByKeys(string memory _path) private {
        string[] memory commands = new string[](3);
        commands[0] = "/bin/bash";
        commands[1] = "-c";
        commands[2] = string.concat("cat <<< $(jq -S '.' ", _path, ") > ", _path);
        vm.ffi(commands);
    }
}

contract GenerateRollupConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        setScriptMode(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateRollupConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateRollupConfig() private {
        // initialize template file
        if (vm.exists(ROLLUP_CONFIG_PATH)) {
            vm.removeFile(ROLLUP_CONFIG_PATH);
        }

        string memory template = vm.readFile(ROLLUP_CONFIG_TEMPLATE_PATH);
        vm.writeFile(ROLLUP_CONFIG_PATH, template);

        // endpoints
        vm.writeJson(L1_RPC_ENDPOINT, ROLLUP_CONFIG_PATH, ".l1_config.endpoint");
        vm.writeJson(L2_RPC_ENDPOINT, ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.sender_config.endpoint");
        vm.writeJson(L2_RPC_ENDPOINT, ROLLUP_CONFIG_PATH, ".l2_config.endpoint");
        vm.writeJson(L1_RPC_ENDPOINT, ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.sender_config.endpoint");

        // contracts
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), ROLLUP_CONFIG_PATH, ".l1_config.l1_message_queue_address");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), ROLLUP_CONFIG_PATH, ".l1_config.scroll_chain_address");
        vm.writeJson(vm.toString(L1_GAS_PRICE_ORACLE_ADDR), ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.gas_price_oracle_contract_address");
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), ROLLUP_CONFIG_PATH, ".l2_config.l2_message_queue_address");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.rollup_contract_address");
        vm.writeJson(vm.toString(L2_GAS_PRICE_ORACLE_PROXY_ADDR), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.gas_price_oracle_contract_address");

        // private keys
        vm.writeJson(vm.toString(bytes32(L1_GAS_ORACLE_SENDER_PRIVATE_KEY)), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.gas_oracle_sender_private_key");
        vm.writeJson(vm.toString(bytes32(L1_COMMIT_SENDER_PRIVATE_KEY)), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.commit_sender_private_key");
        vm.writeJson(vm.toString(bytes32(L1_FINALIZE_SENDER_PRIVATE_KEY)), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.finalize_sender_private_key");
        vm.writeJson(vm.toString(bytes32(L2_GAS_ORACLE_SENDER_PRIVATE_KEY)), ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.gas_oracle_sender_private_key");

        // other
        vm.writeJson(vm.toString(TEST_ENV_MOCK_FINALIZE_ENABLED), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.enable_test_env_bypass_features");
        vm.writeJson(vm.toString(TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.finalize_batch_without_proof_timeout_sec");

        vm.writeJson(vm.toString(MAX_BLOCK_IN_CHUNK), ROLLUP_CONFIG_PATH, ".l2_config.chunk_proposer_config.max_block_num_per_chunk");
        vm.writeJson(vm.toString(MAX_TX_IN_CHUNK), ROLLUP_CONFIG_PATH, ".l2_config.chunk_proposer_config.max_tx_num_per_chunk");

        vm.writeJson(SCROLL_DB_CONNECTION_STRING, ROLLUP_CONFIG_PATH, ".db_config.dsn");
    }
}

contract GenerateCoordinatorConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        setScriptMode(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateCoordinatorConfig();
    }

    /*********************
     * Private functions *
     *********************/

    function generateCoordinatorConfig() private {
        // initialize template file
        if (vm.exists(COORDINATOR_CONFIG_PATH)) {
            vm.removeFile(COORDINATOR_CONFIG_PATH);
        }

        string memory template = vm.readFile(COORDINATOR_CONFIG_TEMPLATE_PATH);
        vm.writeFile(COORDINATOR_CONFIG_PATH, template);

        vm.writeJson(vm.toString(CHAIN_ID_L2), COORDINATOR_CONFIG_PATH, ".l2.chain_id");
        vm.writeJson(SCROLL_DB_CONNECTION_STRING, COORDINATOR_CONFIG_PATH, ".db.dsn");
        vm.writeJson(COORDINATOR_JWT_SECRET_KEY, COORDINATOR_CONFIG_PATH, ".auth.secret");
    }
}

contract GenerateChainMonitorConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        setScriptMode(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateChainMonitorConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateChainMonitorConfig() private {
        // initialize template file
        if (vm.exists(CHAIN_MONITOR_CONFIG_PATH)) {
            vm.removeFile(CHAIN_MONITOR_CONFIG_PATH);
        }

        string memory template = vm.readFile(CHAIN_MONITOR_CONFIG_TEMPLATE_PATH);
        vm.writeFile(CHAIN_MONITOR_CONFIG_PATH, template);

        // L1
        vm.writeJson(L1_RPC_ENDPOINT, CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_url");
        vm.writeJson(vm.toString(L1_CONTRACT_DEPLOYMENT_BLOCK), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.start_number");
        vm.writeJson(vm.toString(L1_ETH_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.eth_gateway");
        vm.writeJson(vm.toString(L1_WETH_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.weth_gateway");
        vm.writeJson(vm.toString(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.standard_erc20_gateway");
        vm.writeJson(vm.toString(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.custom_erc20_gateway");
        vm.writeJson(vm.toString(L1_ERC721_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.erc721_gateway");
        vm.writeJson(vm.toString(L1_ERC1155_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.erc1155_gateway");
        vm.writeJson(vm.toString(L1_SCROLL_MESSENGER_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.scroll_messenger");
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.message_queue");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.scroll_chain");
        vm.writeJson(vm.toString(L2_DEPLOYER_INITIAL_BALANCE), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.start_messenger_balance");

        // L2
        vm.writeJson(L2_RPC_ENDPOINT, CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_url");
        vm.writeJson(vm.toString(L2_ETH_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.eth_gateway");
        vm.writeJson(vm.toString(L2_WETH_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.weth_gateway");
        vm.writeJson(vm.toString(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.standard_erc20_gateway");
        vm.writeJson(vm.toString(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.custom_erc20_gateway");
        vm.writeJson(vm.toString(L2_ERC721_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.erc721_gateway");
        vm.writeJson(vm.toString(L2_ERC1155_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.erc1155_gateway");
        vm.writeJson(vm.toString(L2_SCROLL_MESSENGER_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.scroll_messenger");
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.message_queue");

        // misc
        vm.writeJson(CHAIN_MONITOR_DB_CONNECTION_STRING, CHAIN_MONITOR_CONFIG_PATH, ".db_config.dsn");
    }
}

contract GenerateBridgeHistoryConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        setScriptMode(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateBridgeHistoryConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateBridgeHistoryConfig() private {
        // initialize template file
        if (vm.exists(BRIDGE_HISTORY_CONFIG_PATH)) {
            vm.removeFile(BRIDGE_HISTORY_CONFIG_PATH);
        }

        string memory template = vm.readFile(BRIDGE_HISTORY_CONFIG_TEMPLATE_PATH);
        vm.writeFile(BRIDGE_HISTORY_CONFIG_PATH, template);

        // L1 contracts
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.MessageQueueAddr");
        vm.writeJson(vm.toString(L1_SCROLL_MESSENGER_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.MessengerAddr");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.ScrollChainAddr");
        vm.writeJson(vm.toString(L1_GATEWAY_ROUTER_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.GatewayRouterAddr");
        vm.writeJson(vm.toString(L1_ETH_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.ETHGatewayAddr");
        vm.writeJson(vm.toString(L1_WETH_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.WETHGatewayAddr");
        vm.writeJson(vm.toString(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.StandardERC20GatewayAddr");
        vm.writeJson(vm.toString(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.CustomERC20GatewayAddr");
        vm.writeJson(vm.toString(L1_ERC721_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.ERC721GatewayAddr");
        vm.writeJson(vm.toString(L1_ERC1155_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.ERC1155GatewayAddr");

        // L2 contracts
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.MessageQueueAddr");
        vm.writeJson(vm.toString(L2_SCROLL_MESSENGER_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.MessengerAddr");
        vm.writeJson(vm.toString(L2_GATEWAY_ROUTER_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.GatewayRouterAddr");
        vm.writeJson(vm.toString(L2_ETH_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.ETHGatewayAddr");
        vm.writeJson(vm.toString(L2_WETH_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.WETHGatewayAddr");
        vm.writeJson(vm.toString(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.StandardERC20GatewayAddr");
        vm.writeJson(vm.toString(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.CustomERC20GatewayAddr");
        vm.writeJson(vm.toString(L2_ERC721_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.ERC721GatewayAddr");
        vm.writeJson(vm.toString(L2_ERC1155_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.ERC1155GatewayAddr");

        // endpoints
        vm.writeJson(L1_RPC_ENDPOINT, BRIDGE_HISTORY_CONFIG_PATH, ".L1.endpoint");
        vm.writeJson(L2_RPC_ENDPOINT, BRIDGE_HISTORY_CONFIG_PATH, ".L2.endpoint");

        // others
        vm.writeJson(BRIDGE_HISTORY_DB_CONNECTION_STRING, BRIDGE_HISTORY_CONFIG_PATH, ".db.dsn");
    }
}

contract GenerateBalanceCheckerConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        setScriptMode(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateBalanceCheckerConfig();
    }

    /*********************
     * Private functions *
     *********************/

    function generateBalanceCheckerConfig() private {
        // initialize template file
        if (vm.exists(BALANCE_CHECKER_CONFIG_PATH)) {
            vm.removeFile(BALANCE_CHECKER_CONFIG_PATH);
        }

        string memory template = vm.readFile(BALANCE_CHECKER_CONFIG_TEMPLATE_PATH);
        vm.writeFile(BALANCE_CHECKER_CONFIG_PATH, template);

        vm.writeJson(L1_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[0].rpc_url");
        vm.writeJson(vm.toString(L1_COMMIT_SENDER_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[0].address");

        vm.writeJson(L1_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[1].rpc_url");
        vm.writeJson(vm.toString(L1_FINALIZE_SENDER_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[1].address");

        vm.writeJson(L1_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[2].rpc_url");
        vm.writeJson(vm.toString(L1_GAS_ORACLE_SENDER_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[2].address");

        vm.writeJson(L1_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[3].rpc_url");
        vm.writeJson(vm.toString(L1_FEE_VAULT_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[3].address");

        vm.writeJson(L2_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[4].rpc_url");
        vm.writeJson(vm.toString(L2_GAS_ORACLE_SENDER_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[4].address");

        vm.writeJson(L2_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[5].rpc_url");
        vm.writeJson(vm.toString(L2_TX_FEE_VAULT_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[5].address");
    }
}

contract GenerateFrontendConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        setScriptMode(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateFrontendConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateFrontendConfig() private {
        // use writeFile to start a new file
        vm.writeFile(FRONTEND_ENV_PATH, "REACT_APP_ETH_SYMBOL = \"ETH\"\n");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_BASE_CHAIN = \"Ethereum\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_ROLLUP = \"Scroll Stack\"");
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_CHAIN_ID_L1 = \"", vm.toString(CHAIN_ID_L1), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_CHAIN_ID_L2 = \"", vm.toString(CHAIN_ID_L2), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_CONNECT_WALLET_PROJECT_ID = \"14efbaafcf5232a47d93a68229b71028\"");

        // API endpoints
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_EXTERNAL_RPC_URI_L1 = \"http://l1-devnet.scrollsdk\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_EXTERNAL_RPC_URI_L2 = \"http://l2-rpc.scrollsdk\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_BRIDGE_API_URI = \"http://bridge-history-api.scrollsdk/api\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_ROLLUPSCAN_API_URI = \"https://rollup-explorer-backend.scrollsdk/api\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_EXTERNAL_EXPLORER_URI_L1 = \"http://l1-explorer.scrollsdk\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_EXTERNAL_EXPLORER_URI_L2 = \"http://blockscout.scrollsdk\"");

        // L1 contracts
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = \"", vm.toString(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_ETH_GATEWAY_PROXY_ADDR = \"", vm.toString(L1_ETH_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_GAS_PRICE_ORACLE = \"", vm.toString(L1_GAS_PRICE_ORACLE_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_GATEWAY_ROUTER_PROXY_ADDR = \"", vm.toString(L1_GATEWAY_ROUTER_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_MESSAGE_QUEUE = \"", vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_MESSAGE_QUEUE_WITH_GAS_PRICE_ORACLE = \"", vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_SCROLL_MESSENGER = \"", vm.toString(L1_SCROLL_MESSENGER_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = \"", vm.toString(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_WETH_GATEWAY_PROXY_ADDR = \"", vm.toString(L1_WETH_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_SCROLL_CHAIN = \"", vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), "\""));

        // L2 contracts
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = \"", vm.toString(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_ETH_GATEWAY_PROXY_ADDR = \"", vm.toString(L2_ETH_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_GATEWAY_ROUTER_PROXY_ADDR = \"", vm.toString(L2_GATEWAY_ROUTER_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_SCROLL_MESSENGER = \"", vm.toString(L2_SCROLL_MESSENGER_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR = \"", vm.toString(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_WETH_GATEWAY_PROXY_ADDR = \"", vm.toString(L2_WETH_GATEWAY_PROXY_ADDR), "\""));

        // custom token gateways (currently not set)
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_USDC_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L2_USDC_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_DAI_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L2_DAI_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_LIDO_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L2_LIDO_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_PUFFER_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L2_PUFFER_GATEWAY_PROXY_ADDR = \"\"");

        // misc
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_SCROLL_ORIGINS_NFT = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_SCROLL_ORIGINS_NFT_V2 = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_BATCH_BRIDGE_GATEWAY_PROXY_ADDR = \"\"");
    }
}
