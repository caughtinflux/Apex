#import "STKTableViewCell.h"

#define SELF_WIDTH self.contentView.frame.size.width
#define SELF_HEIGHT self.contentView.frame.size.height

#define TEXT_COLOR [UIColor colorWithRed:76/255.0f green:86/255.0f blue:106/255.0f alpha:1.0f]
#define TEXT_LARGE_FONT [UIFont fontWithName:@"HelveticaNeue" size:72.0f]
#define TEXT_FONT [UIFont fontWithName:@"HelveticaNeue" size:15.0f]

#define TEXT_SHADOW_OFFSET CGSizeMake(0, 1)
#define TEXT_SHADOW_COLOR [UIColor whiteColor]

#define PADDING 9.0f

#define PROFILE_SIZE 78.0f

#define TWITTER_WIDTH 16.0f
#define TWITTER_HEIGHT 13.0f

#define NAME_LABEL_HEIGHT [nameLabel.text sizeWithAttributes:@{NSFontAttributeName:nameLabel.font}].height
#define NAME_LABEL_WIDTH [nameLabel.text sizeWithAttributes:@{NSFontAttributeName:nameLabel.font}].width

#define HANDLE_LABEL_HEIGHT [handleLabel.text sizeWithAttributes:@{NSFontAttributeName:nameLabel.font}].height
#define HANDLE_LABEL_WIDTH [handleLabel.text sizeWithAttributes:@{NSFontAttributeName:nameLabel.font}].width

@implementation STKTableViewCellProfile

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier]))
    {
        profileView = [[[UIImageView alloc] init] autorelease];
        [self.contentView addSubview:profileView];
        
        birdView = [[[UIImageView alloc] init] autorelease];
        birdView.image = [[STKPrefsHelper sharedHelper] ownImageNamed:@"Twitter.png"];
        [self.contentView addSubview:birdView];
        
        nameLabel = [[[UILabel alloc] init] autorelease];
        nameLabel.backgroundColor = [UIColor clearColor];
        nameLabel.font = [UIFont boldSystemFontOfSize:18.0f];
        [self.contentView addSubview:nameLabel];
        
        handleLabel = [[[UILabel alloc] init] autorelease];
        handleLabel.backgroundColor = [UIColor clearColor];
        handleLabel.font = [UIFont systemFontOfSize:16.0f];
        [self.contentView addSubview:handleLabel];
        
        infoLabel = [[[UILabel alloc] init] autorelease];
        infoLabel.backgroundColor = [UIColor clearColor];
        infoLabel.textColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5f];
        infoLabel.font = [UIFont systemFontOfSize:14.0f];
        infoLabel.numberOfLines = 3;
        infoLabel.lineBreakMode = NSLineBreakByWordWrapping;
        
        [self.contentView addSubview:infoLabel];
    }
    return self;
}

static inline CGRect CGRectRound(CGFloat x, CGFloat y, CGFloat width, CGFloat height)
{
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat inverseScale = 1.0f / scale;
    CGRect result;
    result.origin.x = roundf(x * scale) * inverseScale;
    result.size.width = roundf((x + width) * scale) * inverseScale - result.origin.x;
    result.origin.y = roundf(y * scale) * inverseScale;
    result.size.height = roundf((y + height) * scale) * inverseScale - result.origin.y;
    return result;
}

- (void) layoutSubviews
{
    [super layoutSubviews];
    
    profileView.frame = CGRectRound(PADDING, SELF_HEIGHT / 2.0f - (PROFILE_SIZE / 2.0f), PROFILE_SIZE, PROFILE_SIZE);
    birdView.frame = CGRectRound(SELF_WIDTH - TWITTER_WIDTH - PADDING, SELF_HEIGHT / 2.0f - (TWITTER_HEIGHT / 2.0f), TWITTER_WIDTH, TWITTER_HEIGHT);

    nameLabel.frame = CGRectRound(profileView.frame.origin.x + PROFILE_SIZE + PADDING + 1, profileView.frame.origin.y, NAME_LABEL_WIDTH, NAME_LABEL_HEIGHT);
    handleLabel.frame = CGRectRound(nameLabel.frame.origin.x + NAME_LABEL_WIDTH + PADDING - 4, nameLabel.frame.origin.y, HANDLE_LABEL_WIDTH, HANDLE_LABEL_HEIGHT);
    
    infoLabel.frame = CGRectRound(nameLabel.frame.origin.x, nameLabel.frame.origin.y + NAME_LABEL_HEIGHT + 2, birdView.frame.origin.x - nameLabel.frame.origin.x + 2, 55);
}

- (void)loadImage:(NSString *)imageName nameText:(NSString *)nameText handleText:(NSString *)handleText infoText:(NSString *)infoText
{
    profileView.image = [[STKPrefsHelper sharedHelper] ownImageNamed:imageName];
    nameLabel.text = nameText;
    handleLabel.text = handleText;
    infoLabel.text = infoText;
    [self setNeedsLayout];
}

@end
