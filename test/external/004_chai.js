const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('./Chai');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('Chai', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let chai;
    let WETH = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const limits =  toRad(10000);
    const spot  = toRay(1.5);
    const rate  = toRay(1.25);
    const daiDebt = toWad(96);
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    const chi = toRay(1.2);
    const chaiTokens = divRay(daiTokens, chi);

    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(WETH, { from: owner });

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, WETH, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(WETH, spotName, spot, { from: owner });
        await vat.file(WETH, linel, limits, { from: owner });
        await vat.file(Line, limits); 
        await vat.fold(WETH, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );

        // Borrow some dai
        await weth.deposit({ from: owner, value: wethTokens});
        await weth.approve(wethJoin.address, wethTokens, { from: owner }); 
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(WETH, owner, owner, owner, wethTokens, daiDebt, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });

        // Set chi
        await pot.setChi(chi, { from: owner });
    });

    it("allows to exchange dai for chai", async() => {
        assert.equal(
            await dai.balanceOf(owner),   
            daiTokens.toString(),
            "Does not have dai"
        );
        assert.equal(
            await chai.balanceOf(owner),   
            0,
            "Does have Chai",
        );
        
        await dai.approve(chai.address, daiTokens, { from: owner }); 
        await chai.join(owner, daiTokens, { from: owner });

        // Test transfer of chai
        assert.equal(
            await chai.balanceOf(owner),   
            chaiTokens.toString(),
            "Should have chai",
        );
        assert.equal(
            await dai.balanceOf(owner),   
            0,
            "Should not have dai",
        );
    });

    describe("with chai", () => {
        beforeEach(async() => {
            await dai.approve(chai.address, daiTokens, { from: owner }); 
            await chai.join(owner, daiTokens, { from: owner });
        });

        it("allows to exchange chai for dai", async() => {
            assert.equal(
                await chai.balanceOf(owner),   
                chaiTokens.toString(),
                "Does not have chai tokens",
            );
            assert.equal(
                await dai.balanceOf(owner),   
                0,
                "Has dai tokens"
            );
            
            await chai.exit(owner, chaiTokens, { from: owner });

            // Test transfer of chai
            assert.equal(
                await dai.balanceOf(owner),   
                daiTokens.toString(),
                "Should have dai",
            );
            assert.equal(
                await chai.balanceOf(owner),   
                0,
                "Should not have chai",
            );
        });
    });
});