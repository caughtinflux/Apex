#import "STKTableViewCell.h"
#import "Globals.h"

#define SELF_WIDTH self.contentView.frame.size.width
#define SELF_HEIGHT self.contentView.frame.size.height

#define TEXT_COLOR [UIColor colorWithRed:76/255.0f green:86/255.0f blue:106/255.0f alpha:1.0f]
#define TEXT_LARGE_FONT [UIFont fontWithName:@"HelveticaNeue" size:72.0f]
#define TEXT_FONT [UIFont fontWithName:@"HelveticaNeue" size:15.0f]

#define TEXT_SHADOW_OFFSET CGSizeMake(0, 1)
#define TEXT_SHADOW_COLOR [UIColor whiteColor]

#define PADDING 9.0f

#define PROFILE_SIZE 60.0f
#define PROFILE_TOP_PADDING 18.0f

#define HEADER_TOP_PADDING 14.0f

#define MAIN_TOP_PADDING

#define TWITTER_WIDTH 19.0f
#define TWITTER_HEIGHT 15.0f
#define TWITTER_PADDING -5.0f

#define NAME_LABEL_HEIGHT [nameLabel.text sizeWithAttributes:@{NSFontAttributeName: nameLabel.font}].height
#define NAME_LABEL_WIDTH [nameLabel.text sizeWithAttributes:@{NSFontAttributeName: nameLabel.font}].width

#define HANDLE_LABEL_HEIGHT [handleLabel.text sizeWithAttributes:@{NSFontAttributeName: handleLabel.font}].height
#define HANDLE_LABEL_WIDTH [handleLabel.text sizeWithAttributes:@{NSFontAttributeName: handleLabel.font}].width

@implementation STKTableViewCellProfile

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier]))
    {
        profileView = [[UIImageView alloc] init];
        profileView.layer.cornerRadius = PROFILE_SIZE / 2.0f;
        profileView.clipsToBounds = YES;
        [self.contentView addSubview:profileView];
        
        birdView = [[UIImageView alloc] init];
        birdView.image = [[STKPrefsHelper sharedHelper] ownImageNamed:@"Twitter.png"];
        [self.contentView addSubview:birdView];
        
        nameLabel = [[UILabel alloc] init];
        nameLabel.backgroundColor = [UIColor clearColor];
        nameLabel.font = [UIFont boldSystemFontOfSize:18.0f];
        [self.contentView addSubview:nameLabel];
        
        handleLabel = [[UILabel alloc] init];
        handleLabel.backgroundColor = [UIColor clearColor];
        handleLabel.font = [UIFont systemFontOfSize:16.0f];
        [self.contentView addSubview:handleLabel];
        
        infoLabel = [[UILabel alloc] init];
        infoLabel.backgroundColor = [UIColor clearColor];
        infoLabel.textColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5f];
        infoLabel.font = [UIFont systemFontOfSize:14.0f];
        infoLabel.numberOfLines = 3;
        infoLabel.lineBreakMode = NSLineBreakByWordWrapping;
        
        [self.contentView addSubview:infoLabel];
    }
    return self;
}

- (void)dealloc
{
    [profileView release];
    [birdView release];
    [nameLabel release];
    [handleLabel release];
    [infoLabel release];

    [super dealloc];
}

- (void) layoutSubviews
{
    [super layoutSubviews];
    
    profileView.frame = CGRectMake(PADDING, PROFILE_TOP_PADDING, PROFILE_SIZE, PROFILE_SIZE);
    birdView.frame = CGRectMake(SELF_WIDTH - TWITTER_WIDTH - TWITTER_PADDING, SELF_HEIGHT / 2.0f - (TWITTER_HEIGHT / 2.0f), TWITTER_WIDTH, TWITTER_HEIGHT);
    
    nameLabel.frame = CGRectMake(profileView.frame.origin.x + PROFILE_SIZE + PADDING + 1, profileView.frame.origin.y, NAME_LABEL_WIDTH, NAME_LABEL_HEIGHT);
    handleLabel.frame = CGRectMake(nameLabel.frame.origin.x + NAME_LABEL_WIDTH + PADDING, nameLabel.frame.origin.y, HANDLE_LABEL_WIDTH, HANDLE_LABEL_HEIGHT);
    
    infoLabel.frame = CGRectMake(nameLabel.frame.origin.x, nameLabel.frame.origin.y + NAME_LABEL_HEIGHT - 2, birdView.frame.origin.x - nameLabel.frame.origin.x + 2, 55);
}

- (void)loadImage:(NSString *)imageName nameText:(NSString *)nameText handleText:(NSString *)handleText infoText:(NSString *)infoText
{
    if (imageName == nil) profileView.image = nil;
    else profileView.image = [[STKPrefsHelper sharedHelper] ownImageNamed:imageName];
    nameLabel.text = nameText;
    handleLabel.text = handleText;
    infoLabel.text = infoText;
    [self setNeedsLayout];
}

@end
