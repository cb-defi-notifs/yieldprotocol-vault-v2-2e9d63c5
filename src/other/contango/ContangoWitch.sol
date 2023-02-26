// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "../../Witch.sol";
import "./interfaces/IContangoWitchListener.sol";
import "./interfaces/IContangoWitch.sol";

contract ContangoWitch is Witch, IContangoWitch {
    using WMul for uint256;
    using WDiv for uint256;
    using TransferHelper for *;
    using CastU256U128 for uint256;

    struct InsuranceLine {
        uint32 duration; // Time that the insurance auction take to cover the maximum debt insured
        uint64 maxInsuredProportion; // Maximum proportion of debt that is covered by the insurance fund at the insurance auction end (1e18 = 100%)
    }

    IContangoWitchListener public immutable contango;

    mapping(bytes6 => mapping(bytes6 => InsuranceLine)) public insuranceLines;
    address public insuranceFund;

    constructor(IContangoWitchListener contango_, ICauldron cauldron_, ILadle ladle_, address insuranceFund_)
        Witch(cauldron_, ladle_)
    {
        contango = contango_;
        insuranceFund = insuranceFund_;
    }

    function _auctionStarted(bytes12 vaultId, DataTypes.Auction memory auction_, DataTypes.Line memory line)
        internal
        override
        returns (DataTypes.Vault memory vault)
    {
        vault = super._auctionStarted(vaultId, auction_, line);
        contango.auctionStarted(vaultId);
    }

    function _collateralBought(bytes12 vaultId, address buyer, uint256 ink, uint256 art) internal override {
        super._collateralBought(vaultId, buyer, ink, art);
        contango.collateralBought(vaultId, buyer, ink, art);
    }

    function _auctionEnded(bytes12 vaultId, address owner) internal override {
        super._auctionEnded(vaultId, owner);
        contango.auctionEnded(vaultId, owner);
    }

    // TODO auth this
    function setInsuranceLine(bytes6 ilkId, bytes6 baseId, uint32 duration, uint64 maxInsuredProportion)
        external
        override
    {
        insuranceLines[ilkId][baseId] = InsuranceLine(duration, maxInsuredProportion);
        emit InsuranceLineSet(duration, maxInsuredProportion);
    }

    function _discountDebt(bytes6 ilkId, bytes6 baseId, uint256 auctionStart, uint256 auctionDuration, uint256 artIn)
        internal
        view
        virtual
        override
        returns (uint256 requiredArtIn)
    {
        InsuranceLine memory line = insuranceLines[ilkId][baseId];
        requiredArtIn = line.duration == 0 ? artIn : artIn.wmul(_debtProportionNow(line, auctionStart, auctionDuration));
    }

    function _debtProportionNow(InsuranceLine memory line, uint256 auctionStart, uint256 auctionDuration)
        internal
        view
        returns (uint256 debtProportionNow)
    {
        uint256 elapsed = block.timestamp - (auctionStart + auctionDuration);
        uint256 discount =
            elapsed < line.duration ? (line.maxInsuredProportion * elapsed) / line.duration : line.maxInsuredProportion;
        debtProportionNow = ONE_HUNDRED_PERCENT - discount;
    }

    function _topUpDebt(bytes12 vaultId, DataTypes.Auction memory auction, uint256 artIn, bool baseTopUp)
        internal
        override
        returns (uint256 requiredArtIn)
    {
        InsuranceLine memory insuranceLine = insuranceLines[auction.ilkId][auction.baseId];
        uint256 duration = lines[auction.ilkId][auction.baseId].duration;

        if (insuranceLine.duration == 0 || block.timestamp <= auction.start + duration) {
            requiredArtIn = artIn;
        } else {
            requiredArtIn = artIn.wdiv(_debtProportionNow(insuranceLine, auction.start, duration));

            uint256 topUpAmount = requiredArtIn - artIn;

            if (topUpAmount != 0) {
                uint256 debtToppedUp =
                    baseTopUp ? cauldron.debtToBase(auction.seriesId, topUpAmount.u128()) : topUpAmount;

                IFYToken fyToken = cauldron.series(auction.seriesId).fyToken;
                uint256 fyTokenBalance = fyToken.balanceOf(insuranceFund);

                uint256 payWithFYToken = fyTokenBalance > debtToppedUp ? debtToppedUp : fyTokenBalance;
                if (payWithFYToken != 0) {
                    // Take fyTokens from insurance fund
                    fyToken.safeTransferFrom(insuranceFund, address(fyToken), payWithFYToken);
                    fyToken.burn(address(this), payWithFYToken);
                }

                uint256 payWithBase = debtToppedUp - payWithFYToken;
                if (payWithBase != 0) {
                    IJoin baseJoin = ladle.joins(auction.baseId);
                    if (baseJoin == IJoin(address(0))) {
                        revert JoinNotFound(auction.baseId);
                    }

                    // Take underlying from insurance fund
                    IERC20(baseJoin.asset()).safeTransferFrom(insuranceFund, address(baseJoin), payWithBase);
                    baseJoin.join(address(this), payWithBase.u128());
                }

                emit LiquidationInsured(vaultId, topUpAmount, debtToppedUp);
            }
        }
    }
}
