// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/LoanLib.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./BasicMetaTransaction.sol";

/** 
* @title istakpaza: LoanNFT contract
* @notice this contract used to mint the LoanNFTs to the bank via factory 
**/

contract LoanNFT is
    Initializable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    BasicMetaTransaction
{
    address public factory;
    mapping(uint256 => LoanLib.Loan) public loan;
    mapping(address => uint256) public borrower;
    mapping(uint256 => bool) public NFTfreeze;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

/** 
* @notice used to initialize the contract
* @param owner_ address of owner 
**/

function initialize(address owner_) public initializer 
{
        __Ownable_init();
        _transferOwnership(owner_);
        __ERC721_init("LoanNFT", "LNFT");
        __ERC721URIStorage_init();
}

modifier onlyFactory() 
{
        require(_msgSender() == factory, "LoanNFT: only factory ");
        _;
}

/** 
* @notice used to change or update the factory contract
* @param _factory address of factory contract 
**/
function setFactory(address _factory) public onlyOwner 
{
        factory = _factory;
}

/** 
* @notice used to freeze the NFT after the refinance
* @param _tokenId ERC721 tokenID of teh loan
**/
function freezeNFT(uint256 _tokenId) external onlyFactory {
        NFTfreeze[_tokenId] = true;
    }

/** 
* @notice used to mint the ERC721 token to the bank providing the loan
* @param _to address to mint the NFT 
* @param _tokenId tokenid of the  NFT 
* @param _details details of the tokenID 
**/
function mint(
        address _to,
        uint256 _tokenId,
        string memory _tokenURI,
        LoanLib.Loan memory _details
    ) public onlyFactory {
        require(!_exists(_tokenId), "token already exists");
        _safeMint(_to, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
        loan[_tokenId] = _details;
        borrower[_details.borrower] = _tokenId;
    }

/** 
* @notice used to transfer the LoanNFT(ERC721 token)
* @param from address of the NFT holder(bank)
* @param to address to which  the nft  will be transferred 
* @param tokenId tokenID of the LoanNFT
**/
function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override 
{
    require(NFTfreeze[tokenId] != true, "token Freezed");
    super._transfer(from, to, tokenId);
}

/** 
* @notice used to burn the ERC721 token 
* @param _tokenId token id of NFT 
**/

function _burn(uint256 _tokenId) internal virtual override 
{
    require(NFTfreeze[_tokenId] != true, "token Freezed");
    super._burn(_tokenId);
}

/** 
* @notice external function that will call internal _transfer function
* @param to address of ERC721 token holder
* @param tokenId tokenId of ERC721  
**/
function transfer(address to, uint256 tokenId) public onlyOwner 
{
        _transfer(_msgSender(), to, tokenId);
}

/** 
* @notice external function that will call internal _burn function
* @param _tokenId tokenId of ERC721 to be burn 
**/
function burn(uint256 _tokenId) public onlyOwner 
{
        _burn(_tokenId);
}

/** 
* @notice used to transfer the owenrship 
* @param _owner address of new owner
**/
function transferOwnership(address _owner) public override onlyOwner {
        _transferOwnership(_owner);
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