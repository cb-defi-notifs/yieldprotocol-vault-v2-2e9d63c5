// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Vm.sol";
import {TestConstants} from "../utils/TestConstants.sol";
import {TestExtensions} from "../utils/TestExtensions.sol";
import "../../variable/VRLadle.sol";
import "../../variable/VRCauldron.sol";
import "../../variable/VYToken.sol";
import "../../Witch.sol";
import "../../Router.sol";
import "../../oracles/compound/CompoundMultiOracle.sol";
import "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import "../../oracles/accumulator/AccumulatorMultiOracle.sol";
import "../../mocks/oracles/compound/CTokenRateMock.sol";
import "../../mocks/oracles/compound/CTokenChiMock.sol";
import "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import "../../FlashJoin.sol";
import "../../interfaces/ILadle.sol";
import "../../interfaces/ICauldron.sol";
import "../../interfaces/IJoin.sol";
import "../../interfaces/DataTypes.sol";
import "../../variable/interfaces/IVRCauldron.sol";
import "../../mocks/USDCMock.sol";
import "../../mocks/WETH9Mock.sol";
import "../../mocks/DAIMock.sol";
import "../../mocks/ERC20Mock.sol";
import "../../mocks/RestrictedERC20Mock.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
using CastU256I128 for uint256;

abstract contract Fixture is Test, TestConstants, TestExtensions {
    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    VRCauldron public cauldron;
    VRLadle public ladle;
    Witch public witch;
    USDCMock public usdc;
    WETH9Mock public weth;
    DAIMock public dai;
    ERC20Mock public base;
    FlashJoin public usdcJoin;
    FlashJoin public wethJoin;
    FlashJoin public daiJoin;
    FlashJoin public baseJoin;
    bytes6 public usdcId = bytes6("USDC");
    bytes6 public wethId = bytes6("WETH");
    bytes6 public daiId = bytes6("DAI");
    bytes6 public otherIlkId = bytes6("OTHER");
    bytes6 public baseId = bytes6("BASE");
    VYToken public usdcYToken;
    VYToken public wethYToken;
    VYToken public daiYToken;
    CTokenRateMock public cTokenRateMock;
    CTokenChiMock public cTokenChiMock;
    RestrictedERC20Mock public restrictedERC20Mock;
    AccumulatorMultiOracle public chiRateOracle;
    ChainlinkMultiOracle public spotOracle;
    ChainlinkAggregatorV3Mock public ethAggregator;
    ChainlinkAggregatorV3Mock public daiAggregator;
    ChainlinkAggregatorV3Mock public usdcAggregator;
    ChainlinkAggregatorV3Mock public baseAggregator;

    bytes12 public vaultId = 0x000000000000000000000001;
    bytes12 public zeroVaultId = 0x000000000000000000000000;
    bytes12 public otherVaultId = 0x000000000000000000000002;

    bytes6 public zeroId = 0x000000000000;
    bytes6[] public ilkIds;

    uint256 public INK = WAD * 100000;
    uint256 public ART = WAD;
    uint256 public FEE = 1000;

    function setUp() public virtual {
        cauldron = new VRCauldron();
        ladle = new VRLadle(
            IVRCauldron(address(cauldron)),
            IWETH9(address(weth))
        );
        witch = new Witch(ICauldron(address(cauldron)), ILadle(address(ladle)));

        usdc = new USDCMock();
        weth = new WETH9Mock();
        dai = new DAIMock();
        base = new ERC20Mock("Base", "BASE");
        restrictedERC20Mock = new RestrictedERC20Mock("Restricted", "RESTRICTED");

        usdcJoin = new FlashJoin(address(usdc));
        wethJoin = new FlashJoin(address(weth));
        daiJoin = new FlashJoin(address(dai));
        baseJoin = new FlashJoin(address(base));

        setUpOracles();
        // Setting permissions
        ladleGovAuth();
        cauldronGovAuth(address(ladle));
        cauldronGovAuth(address(this));

        makeBase(baseId, address(base), baseJoin, address(chiRateOracle));
    }

    function setUpOracles() internal {
        chiRateOracle = new AccumulatorMultiOracle();

        cTokenRateMock = new CTokenRateMock();
        cTokenRateMock.set(1e18 * 2 * 10000000000);

        cTokenChiMock = new CTokenChiMock();
        cTokenChiMock.set(1e18 * 10000000000);

        chiRateOracle.grantRole(
            AccumulatorMultiOracle.setSource.selector,
            address(this)
        );
        chiRateOracle.setSource(baseId, RATE, WAD, WAD * 2);
        chiRateOracle.setSource(baseId, CHI, WAD, WAD * 2);

        ethAggregator = new ChainlinkAggregatorV3Mock();
        ethAggregator.set(1e18 / 2);

        daiAggregator = new ChainlinkAggregatorV3Mock();
        daiAggregator.set(1e18 / 2);

        usdcAggregator = new ChainlinkAggregatorV3Mock();
        usdcAggregator.set(1e18 / 2);

        baseAggregator = new ChainlinkAggregatorV3Mock();
        baseAggregator.set(1e18 / 2);

        spotOracle = new ChainlinkMultiOracle();
        spotOracle.grantRole(
            ChainlinkMultiOracle.setSource.selector,
            address(this)
        );

        spotOracle.setSource(
            ETH,
            IERC20Metadata(address(weth)),
            usdcId,
            IERC20Metadata(address(usdc)),
            address(usdcAggregator)
        );
        spotOracle.setSource(
            ETH,
            IERC20Metadata(address(weth)),
            baseId,
            IERC20Metadata(address(base)),
            address(ethAggregator)
        );
        spotOracle.setSource(
            ETH,
            IERC20Metadata(address(weth)),
            daiId,
            IERC20Metadata(address(dai)),
            address(daiAggregator)
        );
    }

    // ----------------- Permissions ----------------- //

    function ladleGovAuth() public {
        bytes4[] memory roles = new bytes4[](5);
        roles[0] = VRLadle.addJoin.selector;
        roles[1] = VRLadle.addModule.selector;
        roles[2] = VRLadle.setFee.selector;
        roles[3] = VRLadle.addToken.selector;
        roles[4] = VRLadle.addIntegration.selector;
        ladle.grantRoles(roles, address(this));
    }

    function cauldronGovAuth(address govAuth) public {
        bytes4[] memory roles = new bytes4[](12);
        roles[0] = VRCauldron.addAsset.selector;
        roles[1] = VRCauldron.addIlks.selector;
        roles[2] = VRCauldron.setDebtLimits.selector;
        roles[3] = VRCauldron.setRateOracle.selector;
        roles[4] = VRCauldron.setSpotOracle.selector;
        roles[5] = VRCauldron.addBase.selector;
        roles[6] = VRCauldron.destroy.selector;
        roles[7] = VRCauldron.build.selector;
        roles[8] = VRCauldron.pour.selector;
        roles[9] = VRCauldron.give.selector;
        roles[10] = VRCauldron.tweak.selector;
        roles[11] = VRCauldron.stir.selector;
        cauldron.grantRoles(roles, govAuth);
    }

    // ----------------- Helpers ----------------- //
    function addAsset(
        bytes6 assetId,
        address assetAddress,
        FlashJoin join
    ) public {
        cauldron.addAsset(assetId, assetAddress);
        ladle.addJoin(assetId, join);

        bytes4[] memory roles = new bytes4[](2);
        roles[0] = Join.join.selector;
        roles[1] = Join.exit.selector;
        join.grantRoles(roles, address(ladle));
    }

    function makeBase(
        bytes6 assetId,
        address assetAddress,
        FlashJoin join,
        address chirateoracle
    ) internal {
        addAsset(assetId, assetAddress, join);
        cauldron.setRateOracle(assetId, IOracle(chirateoracle));
        cauldron.addBase(assetId);

        cauldron.setSpotOracle(baseId, baseId, IOracle(chirateoracle), 1000000);
        bytes6[] memory ilk = new bytes6[](1);
        ilk[0] = baseId;
        cauldron.addIlks(baseId, ilk);
        cauldron.setDebtLimits(
            baseId,
            baseId,
            uint96(WAD * 20),
            uint24(1e6),
            18
        );
        cauldron.build(address(this), 0x000000000000000000000003, assetId, assetId);
        IERC20(assetAddress).approve(address(join),INK * 10);
        deal(assetAddress, address(this), INK * 10);
        ladle.pour(0x000000000000000000000003, address(this), (INK * 10).i128(), 0);
    }
}
