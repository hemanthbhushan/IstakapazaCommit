// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./libraries/ControllerLib.sol";
import "./interfaces/IPaza.sol";
import "./interfaces/ITrade.sol";
import "./interfaces/IPool.sol";
import "./interfaces/ILoanNFT.sol";
import "./libraries/LoanLib.sol";
import "./interfaces/IFactory.sol";
import "./BasicMetaTransaction.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title istakpaza Factory contract
 * @notice One of the main contract used to deploy the back pool via cloning the pool contract,
 * whitelist and blacklist the bank pool,
 **/
contract Factory is
    Initializable,
    BasicMetaTransaction,
    IFactory,
    AccessControlUpgradeable
{
    using SafeERC20Upgradeable for IPaza;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IPaza public Paza;
    ITrade public trade;
    IERC20Upgradeable public usdc;
    ILoanNFT public NFT;
    uint256 public constant PCT_BASE = 1000;
    address public masterPool;
    address public postpaidUsdcWallet;
    address public cefiWallet;
    address public prepaidUsdcWallet;
    address public coinbaseWallet;
    address public defiWallet;
    uint256 public borrowerSharePercent;
    uint256 public cefiSharePercent;
    uint256 public defiSharePercent;
    uint256 public otherDefiSharePercent;
    uint256 public otherCefiSharePercent;

    mapping(address => ControllerLib.bankInfo) private banks;

    mapping(address => address) public pools;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isBlacklisted;
    mapping(address => mapping(uint256 => address)) public borrowerBank;

    event DeployPool(address bank, address pool);
    event LoanCreated(
        address borrower,
        address lender,
        uint256 _tokenId,
        uint256 _loanId,
        uint256 _time,
        uint256 _amount,
        uint256 _borrowerShare
    );
    event PoolLoanTransferred(
        address[] _lenders,
        uint256[] _ids,
        address _investor,
        uint256 _time
    );

    event PazaBuyFromUsdcWallet(
        uint256 _serialNo,
        address _lender,
        uint256 _amount
    );

    event PazaBuyFromCoinbase(
        uint256 _serialNo,
        address _lender,
        uint256 coinbaseBalance
    );

    event PostpaidUsdcWalletSet(address postpaidWallet);
    event PrepaidUsdcWalletSet(address prepaidUsdcWallet);
    event CefiWalletSet(address cefiWallet);
    event CoinBaseWallet(address coinbaseWallet);
    event MasterPoolSet(address masterPool);
    event NftContractSet(address nft);
    event UsdcContractSet(address usdc);
    event DefiWalletSet(address defiWallet);
    event SharePercentSet(
        uint256 borrowerSharePercent,
        uint256 cefiSharePercent,
        uint256 defiSharePercent
    );
    event PazaContractSet(address pazaContract);
    event BankWhitelisted(address bank);
    event BankPoolBlacklisted(address bank, address pool);
    event BankDetailsUpdated(address bank, ControllerLib.bankInfo _info);
    event OtherParticipantShareSet(
        uint256 otherDefiShare,
        uint256 otherCeFiShare
    );
    event ParticipantsBuy(uint256 _amount);
    event LoanTenureCompleted(address _bank, address _borrower, uint _loanId);
    event borrowerUnstaked(
        address _bank,
        address _borrower,
        uint _loanId,
        uint rewardAmount,
        uint stakedAmount
    );
    event RewardClaimed(
        address _bank,
        address _borrower,
        uint _loanId,
        uint rewardAmount
    );
    event BlacklistBankLoanTransfer(
        address[] _borrower,
        uint[] _loanId,
        address _blacklistedBank,
        address _auctionWinner
    );
    event SetTradeContract(address _trade);
    event LoanAuctioned(
        address _borrower,
        uint _loanId,
        address _auctionWinner,
        address _bank
    );

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice used to initialize the contract
     * @param _impl address of pool contract
     * @param _paza address of paza token
     * @param _nft address of LoanNFT contract
     * @param _USDCWallet address of Postpaid USDC wallet
     * @param _admin address of admin
     * @param _prepaidUsdcWallet address of PrepaidUSDC wallet
     * @param _usdc address of USDC Contract address
     * @param _coinbaseWallet address of Coinbase wallet
     * @param _defiWallet address of DefiWallet
     * @param _cefiWallet address of CefiWallet
     **/

    function initialize(
        address _impl,
        address _paza,
        address _nft,
        address _USDCWallet,
        address _admin,
        address _prepaidUsdcWallet,
        address _usdc,
        address _coinbaseWallet,
        address _defiWallet,
        address _cefiWallet
    ) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        masterPool = _impl;
        Paza = IPaza(_paza);
        NFT = ILoanNFT(_nft);
        postpaidUsdcWallet = _USDCWallet;
        prepaidUsdcWallet = _prepaidUsdcWallet;
        usdc = IERC20Upgradeable(_usdc);
        coinbaseWallet = _coinbaseWallet;
        defiWallet = _defiWallet;
        cefiWallet = _cefiWallet;
    }

    modifier validation(address _address) {
        require(_address != address(0), "zero address");
        _;
    }

    /**
     * @notice used set the Postpaid USDC wallet
     * @param _wallet address of Postpaid USDC wallet to be updated
     **/
    function setpostpaidUsdcWallet(
        address _wallet
    ) external validation(_wallet) onlyRole(DEFAULT_ADMIN_ROLE) {
        postpaidUsdcWallet = _wallet;
        emit PostpaidUsdcWalletSet(postpaidUsdcWallet);
    }

    /**
     * @notice used to set the Prepaid USDC wallet
     * @param _wallet address of Prepaid USDC wallet
     **/

    function setprepaidUsdcWallet(
        address _wallet
    ) external validation(_wallet) onlyRole(DEFAULT_ADMIN_ROLE) {
        prepaidUsdcWallet = _wallet;
        emit PrepaidUsdcWalletSet(prepaidUsdcWallet);
    }

    /**
     * @notice used to set the Cefi wallet
     * @param _wallet address of Cefi wallet
     **/
    function setCefiWallet(
        address _wallet
    ) external validation(_wallet) onlyRole(DEFAULT_ADMIN_ROLE) {
        cefiWallet = _wallet;
        emit CefiWalletSet(cefiWallet);
    }

    /**
     * @notice used to update the coinBase wallet address
     * @param _wallet address of coinbase wallet
     **/

    function setcoinbaseWallet(
        address _wallet
    ) external validation(_wallet) onlyRole(DEFAULT_ADMIN_ROLE) {
        coinbaseWallet = _wallet;
        emit CoinBaseWallet(coinbaseWallet);
    }

    /**
     * @notice used to update the Pool contract
     * @param _newImplementation address of Pool contract
     **/

    function setMasterPool(
        address _newImplementation
    ) public validation(_newImplementation) onlyRole(DEFAULT_ADMIN_ROLE) {
        masterPool = _newImplementation;
        emit MasterPoolSet(masterPool);
    }

    /**
     * @notice used to update the Trade contract
     * @param _trade address of Trade contract
     **/

    function setTradeContract(
        address _trade
    ) public validation(_trade) onlyRole(DEFAULT_ADMIN_ROLE) {
        trade = ITrade(_trade);
        emit SetTradeContract(_trade);
    }

    /**
     * @notice used to update the LoanNFT contract
     * @param _nft address of LoanNFT contract
     **/
    function setNftContract(
        address _nft
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NFT = ILoanNFT(_nft);
        emit NftContractSet(_nft);
    }

    /**
     * @notice used to update the USDC contract
     * @param _usdc address of USDC contract
     **/

    function setUsdcContract(
        address _usdc
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usdc = IERC20Upgradeable(_usdc);
        emit UsdcContractSet(_usdc);
    }

    /**
     * @notice used to update the Defi wallet
     * @param _defiWallet address of Defi Wallet
     **/

    function setDefiWallet(
        address _defiWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defiWallet = _defiWallet;
        emit DefiWalletSet(defiWallet);
    }

    /**
     * @notice used to set the percentage share of borrower, cefi, Defi
     * @param _sharePercentage array of percentage share with 1000 base
     **/

    function setSharePercent(
        uint256[3] calldata _sharePercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 total;
        for (uint8 i = 0; i < _sharePercentage.length; i++) {
            require(_sharePercentage[i] != 0, "Zero value");
            total += _sharePercentage[i];
        }
        require(total == PCT_BASE, "Not 100 Percent");
        borrowerSharePercent = _sharePercentage[0];
        cefiSharePercent = _sharePercentage[1];
        defiSharePercent = _sharePercentage[2];
        emit SharePercentSet(
            borrowerSharePercent,
            cefiSharePercent,
            defiSharePercent
        );
    }

    /**
     * @notice used to set the percentage share of cefi and Defi for other participants
     * @param _sharePercentage array of percentage share with 1000 base
     **/

    function setOtherParticipantShare(
        uint256[2] calldata _sharePercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _sharePercentage[0] + _sharePercentage[1] == PCT_BASE,
            "Not 100 Percent"
        );
        otherDefiSharePercent = _sharePercentage[0];
        otherCefiSharePercent = _sharePercentage[1];
        emit OtherParticipantShareSet(
            otherDefiSharePercent,
            otherCefiSharePercent
        );
    }

    /**
     * @notice used to update the Paza contract address
     * @param _address address of Paza contract
     **/

    function setPazaContract(
        address _address
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Paza = IPaza(_address);
        emit PazaContractSet(_address);
    }

    /**
     * @notice used to buy Paza by other Participants
     * @param _pazaAmount amount paza with decimals to buy
     **/

    function otherParticipantBuy(
        uint _pazaAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_pazaAmount > 0, "zero amount");
        trade.buyWithApproval(postpaidUsdcWallet, address(this), _pazaAmount);
        Paza.safeTransfer(
            defiWallet,
            (_pazaAmount * otherDefiSharePercent) / PCT_BASE
        );
        Paza.safeTransfer(
            cefiWallet,
            (_pazaAmount * otherCefiSharePercent) / PCT_BASE
        );
        emit ParticipantsBuy(_pazaAmount);
    }

    /**
     * @notice used to deploy the bank pool
     * @param _owner address of the owner
     * @param _bank address of the bank
     **/
    function _deployPool(address _owner, address _bank) internal {
        address impl = Clones.clone(masterPool);
        IPool(impl).initialize(_owner, address(Paza), address(this), _bank);
        pools[_bank] = impl;
        emit DeployPool(_bank, address(impl));
    }

    /**
     * @notice used for minting loan NFT and staking the  paza token to the bank pool
     * @param _to address to mint the tokenID (ERC 721)
     * @param _tokenId _tokenID of ERC 721
     * @param _tokenURI token uri of tokenID
     * @param _details details of Loan
     **/
    function mintLoanNft(
        address _to,
        uint256 _tokenId,
        string memory _tokenURI,
        LoanLib.Loan memory _details
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            isBlacklisted[pools[_details.bank]] != true,
            "Bank Blacklisted"
        );
        require(_to == _details.bank, "Invalid bank");
        require(isWhitelisted[_details.bank] == true, "Bank not whitelisted");
        require(_tokenId == _details.tokenID, "TokenID mismatch");
        require(_details.discount > _details.borrowerShare, "Invalid discount");
        uint256 totalAmount = _details.borrowerShare + _details.ispzIncShare;
        require(
            _details.borrowerShare ==
                (totalAmount * borrowerSharePercent) / PCT_BASE,
            "BorrowerShare mismatch"
        );

        NFT.mint(_to, _tokenId, _tokenURI, _details);
        IPool(pools[_details.bank]).updateUserDetail(
            _details,
            _details.tokenID
        );

        _prepaidPostpaid(_details);
        borrowerBank[_details.borrower][_details.tokenID] = _details.bank;
        IPool(pools[_details.bank]).stake(
            _details.borrower,
            _details.borrowerShare,
            _details.tokenID
        );

        if (_details.isRefinance) {
            require(
                NFT.nftStatus(_details.refinanceTokenID) == false,
                "NFT already freezed"
            );
            NFT.freezeNFT(_details.refinanceTokenID);
            if (
                borrowerBank[_details.borrower][_details.refinanceTokenID] ==
                _details.bank
            ) {
                IPool(pools[_details.bank]).transferStakedAmount(
                    _details.borrower,
                    _details.bank,
                    _details.refinanceTokenID
                );
                IPool(pools[_details.bank]).transferRewards(
                    _details.borrower,
                    _details.refinanceTokenID
                );
            } else {
                IPool(
                    pools[
                        borrowerBank[_details.borrower][
                            _details.refinanceTokenID
                        ]
                    ]
                ).transferRewards(_details.borrower, _details.refinanceTokenID);
            }
        }
        emit LoanCreated(
            _details.borrower,
            _details.bank,
            _tokenId,
            _details.tokenID,
            block.timestamp,
            _details.loanAmount,
            _details.borrowerShare
        );
    }

    /**
     * @notice conditions for prepaid and postpaid type of Loan
     * @param _details details of Loan
     **/
    function _prepaidPostpaid(LoanLib.Loan memory _details) internal {
        uint256 totalPaza = (_details.borrowerShare + _details.ispzIncShare);

        if (_details.isPrepaid) {
            Paza.safeTransferFrom(
                _details.bank,
                defiWallet,
                (totalPaza * defiSharePercent) / PCT_BASE
            );

            Paza.safeTransferFrom(
                _details.bank,
                cefiWallet,
                ((totalPaza) * cefiSharePercent) / PCT_BASE
            );

            Paza.safeTransferFrom(
                _details.bank,
                pools[_details.bank],
                (totalPaza * borrowerSharePercent) / PCT_BASE
            );
        } else {
            trade.buyWithApproval(postpaidUsdcWallet, address(this), totalPaza);
            Paza.safeTransfer(
                defiWallet,
                (totalPaza * defiSharePercent) / PCT_BASE
            );
            Paza.safeTransfer(
                pools[_details.bank],
                (totalPaza * borrowerSharePercent) / PCT_BASE
            );
            Paza.safeTransfer(
                cefiWallet,
                ((totalPaza) * cefiSharePercent) / PCT_BASE
            );
        }
    }

    /**
     * @notice used to transfer the Loan NFTs from the bank to investors
     * @param _lenders addresses of banks(NFT holder)
     * @param _ids Token IDs of LoanNfts
     * @param _investor address of investor
     **/

    function poolLoanTransfer(
        address[] calldata _lenders,
        uint256[] calldata _ids,
        address _investor
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _lenders.length <= 50 && _lenders.length > 0,
            "incorrect length"
        );
        require(_lenders.length == _ids.length, "length not equal");
        for (uint256 i = 0; i < _lenders.length; i++) {
            NFT.safeTransferFrom(_lenders[i], _investor, _ids[i]);
        }

        emit PoolLoanTransferred(_lenders, _ids, _investor, block.timestamp);
    }

    /**
     * @notice used to buy paza
     * @param _lender addresse of bank
     * @param _amount amount paza to buy
     * @param _serialNo serial number for identifying the tx
     **/

    function prepaidPazaBuy(
        address _lender,
        uint256 _amount,
        uint256 _serialNo
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isWhitelisted[_lender] == true, "Not Whitelisted");
        if (usdc.balanceOf(prepaidUsdcWallet) >= (_amount / 10 ** 14)) {
            trade.buyWithApproval(prepaidUsdcWallet, _lender, _amount);

            emit PazaBuyFromUsdcWallet(_serialNo, _lender, _amount);
        } else {
            uint256 coinbaseBalance = usdc.balanceOf(coinbaseWallet);

            require(coinbaseBalance > 0, "Zero Balance");

            usdc.safeTransferFrom(
                coinbaseWallet,
                prepaidUsdcWallet,
                coinbaseBalance
            );

            trade.buyWithApproval(prepaidUsdcWallet, _lender, _amount);

            emit PazaBuyFromCoinbase(_serialNo, _lender, (_amount));
        }
    }

    /**
     * @notice used for updating the bankdetails
     * @param _bank address of bank
     * @param _info bank info
     **/
    function updateBankDetails(
        address _bank,
        ControllerLib.bankInfo memory _info
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isWhitelisted[_bank] == true, "Bank Not Whitelisted");
        banks[_bank] = _info;
        emit BankDetailsUpdated(_bank, _info);
    }

    /**
     * @notice used for whitelisting the bank
     * @param _owner address of owner
     * @param _bank address of bank
     * @param _info bank info
     **/
    function whitelistBank(
        address _owner,
        address _bank,
        ControllerLib.bankInfo memory _info
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isWhitelisted[_bank] == false, "Already Whitelisted");
        banks[_bank] = _info;
        _deployPool(_owner, _bank);
        isWhitelisted[_bank] = true;
        emit BankWhitelisted(_bank);
    }

    /**
     * @notice used for blacklisting the bank pool
     * @param _bank address of bank
     **/
    function blackListBankPool(
        address _bank
    ) public validation(_bank) onlyRole(DEFAULT_ADMIN_ROLE) {
        isBlacklisted[pools[_bank]] = true;
        emit BankPoolBlacklisted(_bank, pools[_bank]);
    }

    /**
     * @notice used to check if the bank is blacklisted
     * @param _bank address of bank
     * @return true if bank is blacklisted and false if bank is not blacklisted
     **/
    function isBankPoolBlacklisted(address _bank) public view returns (bool) {
        return isBlacklisted[pools[_bank]];
    }

    /**
     * @notice used for checking the bank info
     * @param _bank address of bank
     * @return struct of bank info
     **/
    function checkBankInfo(
        address _bank
    ) external view returns (ControllerLib.bankInfo memory) {
        return banks[_bank];
    }

    /**
     * @notice used to transfer the loan from blacklisted bank to other bank
     * @param _borrower array of borrowers addresses
     * @param _loanId array of loanIds
     * @param _blacklistedBank address of blacklisted bank
     * @param _auctionWinner address of an auction Winner
     **/

    function loanTransferOfBlacklistedBank(
        address[] calldata _borrower,
        uint[] calldata _loanId,
        address _blacklistedBank,
        address _auctionWinner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isWhitelisted[_auctionWinner] == true, "Bank Not Whitelisted");
        require(_borrower.length == _loanId.length, "length mismatch");
        require(_borrower.length <= 20, "Max 20 loans allowed");
        if (Paza.balanceOf(pools[_blacklistedBank]) > 0) {
            IPool(pools[_blacklistedBank]).removeTokensOfBlacklistedBank(
                _auctionWinner
            );
        }
        for (uint i = 0; i < _borrower.length; i++) {
            require(
                borrowerBank[_borrower[i]][_loanId[i]] == _blacklistedBank,
                "Invalid loan"
            );
            NFT.safeTransferFrom(_blacklistedBank, _auctionWinner, _loanId[i]);
            borrowerBank[_borrower[i]][_loanId[i]] = _auctionWinner;

            LoanLib.Loan memory loanDetails = IPool(pools[_blacklistedBank])
                .getUserDetails(_borrower[i], _loanId[i]);
            loanDetails.bank = _auctionWinner;
            loanDetails.discount = 0;
            loanDetails.borrowerShare = 0;
            loanDetails.disbursementInterval = 0;
            IPool(pools[_auctionWinner]).updateUserDetail(
                loanDetails,
                loanDetails.tokenID
            );
        }
        emit BlacklistBankLoanTransfer(
            _borrower,
            _loanId,
            _blacklistedBank,
            _auctionWinner
        );
    }

    /**
     * @notice used to transfer stakedAmount to AuctionWinner
     * @param _borrower address of borrower
     * @param _loanId loanId
     * @param _auctionWinner address of an auction Winner
     * @param _bank bank address
     **/

    function singleLoanAuction(
        address _borrower,
        uint _loanId,
        address _auctionWinner,
        address _bank
    ) external {
        require(isWhitelisted[_auctionWinner] == true, "Bank Not Whitelisted");
        IPool(pools[_bank]).transferStakedAmount(
            _borrower,
            _auctionWinner,
            _loanId
        );
        emit LoanAuctioned(_borrower, _loanId, _auctionWinner, _bank);
    }

    /**
     * @notice used to freeze the nft once loan tenure is over
     * @param _bank bank address
     * @param _borrower address of borrower
     * @param _loanId loanId
     **/

    function completeTenure(
        address _bank,
        address _borrower,
        uint _loanId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        LoanLib.Loan memory loanDetails = IPool(pools[_bank]).getUserDetails(
            _borrower,
            _loanId
        );
        require(block.timestamp > loanDetails.loanTenure, "Tenure not over");
        NFT.freezeNFT(_loanId);
        emit LoanTenureCompleted(_bank, _borrower, _loanId);
    }

    function _msgSender()
        internal
        view
        override(ContextUpgradeable, BasicMetaTransaction)
        returns (address sender)
    {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(
                    mload(add(array, index)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
        } else {
            return msg.sender;
        }
    }
}