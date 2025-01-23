use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Mint};

declare_id!("HcuPhydFQWnGPg6jXwG7G5v2Ygso7RQ8KaNFAFBL1cJe");

#[program]
pub mod launchpad {
    use super::*;

    // Structure to store project information
    #[account]
    pub struct ProjectInfo {
        // Project admin who can modify settings
        pub admin: Pubkey,
        // Token being sold in the launchpad
        pub token_mint: Pubkey,
        // Start time of the sale
        pub start_time: i64,
        // End time of the sale
        pub end_time: i64,
        // Token price in lamports (1 SOL = 1_000_000_000 lamports)
        pub token_price: u64,
        // Total tokens allocated for sale
        pub total_tokens: u64,
        // Tokens already sold
        pub tokens_sold: u64,
        // Minimum purchase amount in tokens
        pub min_purchase: u64,
        // Maximum purchase amount per wallet
        pub max_purchase: u64,
    }

    // Initialize a new launchpad project
    pub fn initialize_project(
        ctx: Context<InitializeProject>,
        start_time: i64,
        end_time: i64,
        token_price: u64,
        total_tokens: u64,
        min_purchase: u64,
        max_purchase: u64,
    ) -> Result<()> {
        let project_info = &mut ctx.accounts.project_info;
        
        // Validate time parameters
        require!(end_time > start_time, LaunchpadError::InvalidTimeRange);
        require!(start_time > Clock::get()?.unix_timestamp, LaunchpadError::InvalidStartTime);

        // Initialize project state
        project_info.admin = ctx.accounts.admin.key();
        project_info.token_mint = ctx.accounts.token_mint.key();
        project_info.start_time = start_time;
        project_info.end_time = end_time;
        project_info.token_price = token_price;
        project_info.total_tokens = total_tokens;
        project_info.tokens_sold = 0;
        project_info.min_purchase = min_purchase;
        project_info.max_purchase = max_purchase;

        Ok(())
    }

    // Purchase tokens from the launchpad
    pub fn purchase_tokens(
        ctx: Context<PurchaseTokens>,
        amount: u64
    ) -> Result<()> {
        let project_info = &mut ctx.accounts.project_info;
        let clock = Clock::get()?;

        // Check if sale is active
        require!(
            clock.unix_timestamp >= project_info.start_time 
            && clock.unix_timestamp <= project_info.end_time,
            LaunchpadError::SaleInactive
        );

        // Validate purchase amount
        require!(amount >= project_info.min_purchase, LaunchpadError::BelowMinimum);
        require!(amount <= project_info.max_purchase, LaunchpadError::AboveMaximum);
        require!(
            project_info.tokens_sold.checked_add(amount).unwrap() <= project_info.total_tokens,
            LaunchpadError::InsufficientTokens
        );

        // Calculate price in lamports
        let price = amount.checked_mul(project_info.token_price).unwrap();

        // Transfer SOL from buyer to project vault
        let transfer_sol_ix = anchor_lang::solana_program::system_instruction::transfer(
            &ctx.accounts.buyer.key(),
            &ctx.accounts.project_vault.key(),
            price,
        );
        anchor_lang::solana_program::program::invoke(
            &transfer_sol_ix,
            &[
                ctx.accounts.buyer.to_account_info(),
                ctx.accounts.project_vault.to_account_info(),
            ],
        )?;

        // Transfer tokens to buyer
        token::transfer(
            CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                token::Transfer {
                    from: ctx.accounts.token_vault.to_account_info(),
                    to: ctx.accounts.buyer_token_account.to_account_info(),
                    authority: ctx.accounts.project_vault.to_account_info(),
                },
            ),
            amount,
        )?;

        // Update state
        project_info.tokens_sold = project_info.tokens_sold.checked_add(amount).unwrap();

        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitializeProject<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    
    #[account(
        init,
        payer = admin,
        space = 8 + 32 + 32 + 8 + 8 + 8 + 8 + 8 + 8 + 8
    )]
    pub project_info: Account<'info, ProjectInfo>,
    
    pub token_mint: Account<'info, Mint>,
    
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PurchaseTokens<'info> {
    #[account(mut)]
    pub project_info: Account<'info, ProjectInfo>,
    
    #[account(mut)]
    pub buyer: Signer<'info>,
    
    /// CHECK: Safe because we're only using it as a vault
    #[account(mut)]
    pub project_vault: AccountInfo<'info>,
    
    #[account(mut)]
    pub token_vault: Account<'info, TokenAccount>,
    
    #[account(mut)]
    pub buyer_token_account: Account<'info, TokenAccount>,
    
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[error_code]
pub enum LaunchpadError {
    #[msg("Sale is not active")]
    SaleInactive,
    #[msg("Purchase amount below minimum")]
    BelowMinimum,
    #[msg("Purchase amount above maximum")]
    AboveMaximum,
    #[msg("Insufficient tokens remaining")]
    InsufficientTokens,
    #[msg("Invalid time range")]
    InvalidTimeRange,
    #[msg("Invalid start time")]
    InvalidStartTime,
}
